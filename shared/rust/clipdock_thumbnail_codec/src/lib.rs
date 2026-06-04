pub use clipdock_sync_contract::{
    THUMBNAIL_DETAIL_TARGET_BYTES as DETAIL_TARGET_BYTES, THUMBNAIL_MAX_BYTES as MAX_BYTES,
    THUMBNAIL_NORMAL_TARGET_BYTES as NORMAL_TARGET_BYTES,
};

pub const CANDIDATES: &[(u32, u8)] = &[
    (420, 92),
    (420, 86),
    (420, 80),
    (384, 86),
    (384, 80),
    (360, 80),
    (320, 82),
    (320, 76),
    (288, 76),
    (256, 76),
    (224, 74),
];

#[derive(Clone, Debug)]
pub struct AdaptiveThumbnail {
    pub bytes: Vec<u8>,
    pub width: u32,
    pub height: u32,
    pub quality: u8,
    pub score: f64,
    pub tier: String,
}

#[derive(Clone, Debug)]
struct CandidateResult {
    bytes: Vec<u8>,
    width: u32,
    height: u32,
    quality: u8,
    score: f64,
    tier: String,
}

pub fn encode_adaptive_thumbnail_webp_rgba(
    rgba: &[u8],
    width: u32,
    height: u32,
    normal_target: usize,
    detail_target: usize,
    max_bytes: usize,
) -> Result<Option<AdaptiveThumbnail>, &'static str> {
    if width == 0 || height == 0 {
        return Err("invalid_input");
    }
    if normal_target == 0 || detail_target < normal_target || max_bytes < detail_target {
        return Err("invalid_input");
    }
    let expected_len = (width as usize)
        .checked_mul(height as usize)
        .and_then(|pixel_count| pixel_count.checked_mul(4))
        .ok_or("invalid_input")?;
    if rgba.len() != expected_len {
        return Err("invalid_input");
    }

    let mut encoded = Vec::with_capacity(CANDIDATES.len());
    for (max_dimension, quality) in CANDIDATES {
        let (candidate_width, candidate_height) = fit_dimensions(width, height, *max_dimension);
        let candidate_rgba =
            resize_rgba_nearest(rgba, width, height, candidate_width, candidate_height)?;
        let bytes =
            encode_lossy_webp_rgba(&candidate_rgba, candidate_width, candidate_height, *quality)?;
        if bytes.len() > max_bytes {
            continue;
        }
        let decoded = decode_webp_rgba(&bytes)?;
        if decoded.width != candidate_width || decoded.height != candidate_height {
            return Err("decode_size_mismatch");
        }
        let score = if candidate_width < 8 || candidate_height < 8 {
            100.0
        } else {
            let reference_rgb = rgba_to_rgb_pixels(&candidate_rgba);
            let decoded_rgb = rgba_to_rgb_pixels(&decoded.rgba);
            let source = imgref::Img::new(
                reference_rgb,
                candidate_width as usize,
                candidate_height as usize,
            );
            let distorted = imgref::Img::new(
                decoded_rgb,
                candidate_width as usize,
                candidate_height as usize,
            );
            fast_ssim2::compute_ssimulacra2(source.as_ref(), distorted.as_ref())
                .map_err(|_| "scoring_failed")?
        };
        encoded.push(CandidateResult {
            bytes,
            width: candidate_width,
            height: candidate_height,
            quality: *quality,
            score,
            tier: String::new(),
        });
    }

    if let Some(mut candidate) = encoded
        .iter()
        .find(|candidate| candidate.bytes.len() <= normal_target && candidate.score >= 80.0)
        .cloned()
    {
        candidate.tier = "normal".to_string();
        return Ok(Some(candidate.into()));
    }
    if let Some(mut candidate) = encoded
        .iter()
        .find(|candidate| candidate.bytes.len() <= detail_target && candidate.score >= 88.0)
        .cloned()
    {
        candidate.tier = "detail".to_string();
        return Ok(Some(candidate.into()));
    }
    let mut best = encoded
        .into_iter()
        .max_by(|lhs, rhs| lhs.score.total_cmp(&rhs.score));
    if let Some(candidate) = best.as_mut() {
        candidate.tier = "fallback".to_string();
    }
    Ok(best.map(Into::into))
}

impl From<CandidateResult> for AdaptiveThumbnail {
    fn from(value: CandidateResult) -> Self {
        Self {
            bytes: value.bytes,
            width: value.width,
            height: value.height,
            quality: value.quality,
            score: value.score,
            tier: value.tier,
        }
    }
}

struct DecodedWebP {
    rgba: Vec<u8>,
    width: u32,
    height: u32,
}

fn encode_lossy_webp_rgba(
    rgba: &[u8],
    width: u32,
    height: u32,
    quality: u8,
) -> Result<Vec<u8>, &'static str> {
    let config = zenwebp::LossyConfig::new()
        .with_quality(f32::from(quality))
        .with_method(4);
    zenwebp::EncodeRequest::lossy(&config, rgba, zenwebp::PixelLayout::Rgba8, width, height)
        .encode()
        .map_err(|_| "encoding_failed")
}

fn decode_webp_rgba(bytes: &[u8]) -> Result<DecodedWebP, &'static str> {
    let (rgba, width, height) =
        zenwebp::oneshot::decode_rgba(bytes).map_err(|_| "decode_failed")?;
    Ok(DecodedWebP {
        rgba,
        width,
        height,
    })
}

fn fit_dimensions(width: u32, height: u32, max_dimension: u32) -> (u32, u32) {
    let largest = width.max(height);
    if largest <= max_dimension {
        return (width, height);
    }
    let scale = max_dimension as f64 / largest as f64;
    let target_width = ((width as f64 * scale).round() as u32).max(1);
    let target_height = ((height as f64 * scale).round() as u32).max(1);
    (target_width, target_height)
}

fn resize_rgba_nearest(
    rgba: &[u8],
    width: u32,
    height: u32,
    target_width: u32,
    target_height: u32,
) -> Result<Vec<u8>, &'static str> {
    if width == target_width && height == target_height {
        return Ok(rgba.to_vec());
    }
    let output_len = (target_width as usize)
        .checked_mul(target_height as usize)
        .and_then(|pixel_count| pixel_count.checked_mul(4))
        .ok_or("invalid_input")?;
    let mut output = vec![0; output_len];
    for target_y in 0..target_height {
        let source_y = (u64::from(target_y) * u64::from(height) / u64::from(target_height)) as u32;
        for target_x in 0..target_width {
            let source_x =
                (u64::from(target_x) * u64::from(width) / u64::from(target_width)) as u32;
            let source_index = ((source_y * width + source_x) as usize) * 4;
            let target_index = ((target_y * target_width + target_x) as usize) * 4;
            output[target_index..target_index + 4]
                .copy_from_slice(&rgba[source_index..source_index + 4]);
        }
    }
    Ok(output)
}

fn rgba_to_rgb_pixels(rgba: &[u8]) -> Vec<[u8; 3]> {
    rgba.chunks_exact(4)
        .map(|pixel| [pixel[0], pixel[1], pixel[2]])
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tiny_input_uses_deterministic_score_path() {
        let rgba = vec![255; 4 * 4 * 4];
        let result = encode_adaptive_thumbnail_webp_rgba(
            &rgba,
            4,
            4,
            NORMAL_TARGET_BYTES,
            DETAIL_TARGET_BYTES,
            MAX_BYTES,
        )
        .expect("encode")
        .expect("candidate");

        assert_eq!(4, result.width);
        assert_eq!(4, result.height);
        assert_eq!(100.0, result.score);
        assert!(result.bytes.len() <= NORMAL_TARGET_BYTES);
    }

    #[test]
    fn invalid_buffer_length_is_rejected() {
        let error = encode_adaptive_thumbnail_webp_rgba(
            &[0; 3],
            2,
            2,
            NORMAL_TARGET_BYTES,
            DETAIL_TARGET_BYTES,
            MAX_BYTES,
        )
        .unwrap_err();

        assert_eq!("invalid_input", error);
    }
}
