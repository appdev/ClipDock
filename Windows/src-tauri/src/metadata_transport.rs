use std::time::{Duration, Instant};

use reqwest::{header, redirect::Policy, Client, StatusCode};
use url::Url;

pub(crate) struct MetadataTransport {
    client: Client,
    page_timeout: Duration,
    image_timeout: Duration,
    max_redirects: usize,
}

pub(super) struct MetadataDownload {
    pub final_url: Url,
    pub content_type: String,
    pub bytes: Vec<u8>,
}

impl MetadataTransport {
    pub fn new(
        page_timeout: Duration,
        image_timeout: Duration,
        max_redirects: usize,
    ) -> Result<Self, String> {
        let client = Client::builder()
            .timeout(page_timeout.max(image_timeout))
            .redirect(Policy::none())
            .user_agent("ClipDock-Tauri-Panel/0.1")
            .build()
            .map_err(|error| error.without_url().to_string())?;
        Ok(Self {
            client,
            page_timeout,
            image_timeout,
            max_redirects,
        })
    }

    pub(super) async fn get(
        &self,
        mut url: Url,
        byte_limit: usize,
        image_only: bool,
        policy: impl Fn(&Url) -> Result<(), String>,
    ) -> Result<MetadataDownload, String> {
        let started = Instant::now();
        let timeout = if image_only {
            self.image_timeout
        } else {
            self.page_timeout
        };
        let mut redirects = 0;
        loop {
            policy(&url)?;
            let remaining = timeout
                .checked_sub(started.elapsed())
                .filter(|value| !value.is_zero())
                .ok_or("metadata request timed out")?;
            let mut response = self
                .client
                .get(url.clone())
                .timeout(remaining)
                .send()
                .await
                .map_err(|error| error.without_url().to_string())?;
            if matches!(
                response.status(),
                StatusCode::MOVED_PERMANENTLY
                    | StatusCode::FOUND
                    | StatusCode::SEE_OTHER
                    | StatusCode::TEMPORARY_REDIRECT
                    | StatusCode::PERMANENT_REDIRECT
            ) {
                if redirects >= self.max_redirects {
                    return Err("metadata redirect limit exceeded".into());
                }
                let location = response
                    .headers()
                    .get(header::LOCATION)
                    .and_then(|value| value.to_str().ok())
                    .ok_or("metadata redirect location missing")?;
                url = url
                    .join(location)
                    .map_err(|_| "metadata redirect URL is invalid")?;
                redirects += 1;
                // Dropping the response cancels its unused body. The next loop
                // checks policy before any request to the redirect destination.
                continue;
            }
            if !response.status().is_success() {
                return Err(format!("metadata request returned {}", response.status()));
            }
            let content_type = response
                .headers()
                .get(header::CONTENT_TYPE)
                .and_then(|value| value.to_str().ok())
                .unwrap_or("")
                .to_ascii_lowercase();
            if image_only && !content_type.is_empty() && !content_type.starts_with("image/") {
                return Err("metadata image has unsupported content type".into());
            }
            if response
                .content_length()
                .is_some_and(|length| length > byte_limit as u64)
            {
                return Err("metadata body exceeds byte budget".into());
            }
            let mut bytes = Vec::new();
            while let Some(chunk) = response
                .chunk()
                .await
                .map_err(|error| error.without_url().to_string())?
            {
                if chunk.len() > byte_limit.saturating_sub(bytes.len()) {
                    // Never retain an oversized chunk or read another one.
                    return Err("metadata body exceeds byte budget".into());
                }
                bytes.extend_from_slice(&chunk);
            }
            return Ok(MetadataDownload {
                final_url: url,
                content_type,
                bytes,
            });
        }
    }
}

#[cfg(test)]
pub(super) mod tests {
    use super::*;
    use std::{
        io::{Read, Write},
        net::TcpListener,
        sync::{Arc, Mutex},
        thread,
    };

    pub(crate) fn server(responses: Vec<String>) -> (Url, thread::JoinHandle<Vec<String>>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        listener.set_nonblocking(true).unwrap();
        let url = Url::parse(&format!("http://{}/start", listener.local_addr().unwrap())).unwrap();
        let worker = thread::spawn(move || {
            let deadline = Instant::now() + Duration::from_secs(3);
            let mut requests = Vec::new();
            for response in responses {
                let mut stream = loop {
                    match listener.accept() {
                        Ok((stream, _)) => break stream,
                        Err(error)
                            if error.kind() == std::io::ErrorKind::WouldBlock
                                && Instant::now() < deadline =>
                        {
                            thread::sleep(Duration::from_millis(1))
                        }
                        Err(error) => panic!("local fixture request missing: {error}"),
                    }
                };
                // Accepted sockets can inherit O_NONBLOCK on macOS. Fixture I/O
                // must honor the timeout instead of racing the request writer.
                stream.set_nonblocking(false).unwrap();
                stream
                    .set_read_timeout(Some(Duration::from_secs(1)))
                    .unwrap();
                let mut request = Vec::new();
                let mut byte = [0];
                while !request.ends_with(b"\r\n\r\n") {
                    stream.read_exact(&mut byte).unwrap();
                    request.push(byte[0]);
                }
                requests.push(String::from_utf8(request).unwrap());
                let _ = stream.write_all(response.as_bytes());
            }
            requests
        });
        (url, worker)
    }

    fn allow_http(url: &Url) -> Result<(), String> {
        if matches!(url.scheme(), "http" | "https") {
            Ok(())
        } else {
            Err("unsupported URL".into())
        }
    }

    #[test]
    fn body_budget_covers_unadvertised_chunked_and_content_length_responses() {
        tauri::async_runtime::block_on(async {
            let transport =
                MetadataTransport::new(Duration::from_secs(2), Duration::from_secs(2), 2).unwrap();
            for response in [
                "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n123456789",
                "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n4\r\n1234\r\n5\r\n56789\r\n0\r\n\r\n",
                "HTTP/1.1 200 OK\r\nContent-Length: 9\r\nConnection: close\r\n\r\n123456789",
            ] {
                let (url, worker) = server(vec![response.into()]);
                assert!(matches!(transport.get(url, 8, false, allow_http).await, Err(error) if error == "metadata body exceeds byte budget"));
                assert_eq!(worker.join().unwrap().len(), 1);
            }
            let (url, worker) = server(vec![
                "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n12345678".into(),
            ]);
            assert_eq!(
                transport
                    .get(url, 8, false, allow_http)
                    .await
                    .unwrap()
                    .bytes,
                b"12345678"
            );
            worker.join().unwrap();
        });
    }

    #[test]
    fn oversized_stream_is_dropped_without_waiting_for_its_end() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = Url::parse(&format!("http://{}/stream", listener.local_addr().unwrap())).unwrap();
        let (release_tx, release_rx) = std::sync::mpsc::channel();
        let worker = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            stream
                .set_read_timeout(Some(Duration::from_secs(2)))
                .unwrap();
            let mut request = Vec::new();
            let mut byte = [0];
            while !request.ends_with(b"\r\n\r\n") {
                stream.read_exact(&mut byte).unwrap();
                request.push(byte[0]);
            }
            // Deliberately never terminate the body before the client returns.
            stream.write_all(b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n9\r\n123456789\r\n").unwrap();
            let _ = release_rx.recv_timeout(Duration::from_secs(3));
        });
        let result = tauri::async_runtime::block_on(async {
            MetadataTransport::new(Duration::from_secs(2), Duration::from_secs(2), 2)
                .unwrap()
                .get(url, 8, false, allow_http)
                .await
        });
        let _ = release_tx.send(());
        worker.join().unwrap();
        assert!(matches!(result, Err(error) if error == "metadata body exceeds byte budget"));
    }

    #[test]
    fn redirect_destinations_are_checked_before_network_and_hops_are_bounded() {
        tauri::async_runtime::block_on(async {
            let transport =
                MetadataTransport::new(Duration::from_secs(2), Duration::from_secs(2), 2).unwrap();
            let (url, worker) = server(vec!["HTTP/1.1 302 Found\r\nLocation: /private?token=fixture\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".into()]);
            let checked = Arc::new(Mutex::new(Vec::new()));
            let checks = checked.clone();
            let result = transport
                .get(url, 8, false, move |url| {
                    checks.lock().unwrap().push(url.path().to_string());
                    if url.query_pairs().any(|(key, _)| key == "token") {
                        Err("private query".into())
                    } else {
                        Ok(())
                    }
                })
                .await;
            assert!(matches!(result, Err(error) if error == "private query"));
            assert_eq!(*checked.lock().unwrap(), ["/start", "/private"]);
            assert_eq!(worker.join().unwrap().len(), 1);
            let redirect = "HTTP/1.1 302 Found\r\nLocation: /loop\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
            let (url, worker) = server(vec![redirect.into(); 3]);
            assert!(
                matches!(transport.get(url, 8, false, allow_http).await, Err(error) if error == "metadata redirect limit exceeded")
            );
            assert_eq!(worker.join().unwrap().len(), 3);
        });
    }

    #[test]
    fn relative_redirects_return_the_final_base_and_images_validate_mime() {
        tauri::async_runtime::block_on(async {
            let transport =
                MetadataTransport::new(Duration::from_secs(2), Duration::from_secs(2), 2).unwrap();
            let (url, worker) = server(vec![
                "HTTP/1.1 302 Found\r\nLocation: /resolved/page\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".into(),
                "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\nok".into(),
            ]);
            let result = transport.get(url, 8, false, allow_http).await.unwrap();
            assert_eq!(result.final_url.path(), "/resolved/page");
            assert_eq!(result.bytes, b"ok");
            assert_eq!(worker.join().unwrap().len(), 2);
            let (url, worker) = server(vec![
                "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\nnot image"
                    .into(),
            ]);
            assert!(
                matches!(transport.get(url, 8, true, allow_http).await, Err(error) if error.contains("content type"))
            );
            worker.join().unwrap();
        });
    }
}
