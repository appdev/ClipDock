package com.apkdv.clipdock;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.widget.TextView;

public final class ForegroundClipboardSourceActivity extends Activity {
  private static final String EXTRA_TEXT = "text";
  private static final String EXTRA_MODE = "mode";
  private static final String EXTRA_READ_ID = "readId";
  private static final String MODE_READ = "read";

  private final Handler handler = new Handler(Looper.getMainLooper());

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    ClipboardManager clipboard = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
    if (MODE_READ.equals(getIntent().getStringExtra(EXTRA_MODE))) {
      String readId = getIntent().getStringExtra(EXTRA_READ_ID);
      TextView probe = new TextView(this);
      probe.setText("pending");
      probe.setContentDescription("clipboard-probe:" + readId + ":pending");
      setContentView(probe);
      handler.postDelayed(
          () -> {
            String text = "";
            ClipData clip = clipboard.getPrimaryClip();
            if (clip != null && clip.getItemCount() > 0 && clip.getItemAt(0).getText() != null) {
              text = clip.getItemAt(0).getText().toString();
            }
            probe.setText(text);
            probe.setContentDescription("clipboard-probe:" + readId + ":" + text);
          },
          600);
      handler.postDelayed(this::finishAndRemoveTask, 3000);
    } else {
      String text = getIntent().getStringExtra(EXTRA_TEXT);
      if (text == null) {
        text = "";
      }
      final String copyText = text;
      TextView writer = new TextView(this);
      writer.setText("copying");
      setContentView(writer);
      handler.postDelayed(
          () -> clipboard.setPrimaryClip(ClipData.newPlainText("foreground source copy", copyText)),
          600);
      handler.postDelayed(this::finishAndRemoveTask, 1500);
    }
  }
}
