package com.ilesong.castlerpg.notify;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

/** 예약 시각에 알림을 띄운다. 누르면 게임이 열린다. */
public class NotifyReceiver extends BroadcastReceiver {
    static final String CHANNEL = "castle_game";
    private static final int ACCENT = 0xFFC8962E;

    @Override
    public void onReceive(Context c, Intent intent) {
        int id = intent.getIntExtra(Alarms.EXTRA_ID, 0);
        String title = intent.getStringExtra(Alarms.EXTRA_TITLE);
        String body = intent.getStringExtra(Alarms.EXTRA_BODY);
        Store.remove(c, id);
        if (title == null || body == null) {
            return;
        }
        NotificationManager nm = c.getSystemService(NotificationManager.class);
        if (nm == null) {
            return;
        }
        Notification.Builder b;
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(new NotificationChannel(CHANNEL, "게임 알림", NotificationManager.IMPORTANCE_DEFAULT));
            b = new Notification.Builder(c, CHANNEL);
        } else {
            b = new Notification.Builder(c);
        }
        b.setSmallIcon(R.drawable.castle_notify_icon)
                .setColor(ACCENT)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(new Notification.BigTextStyle().bigText(body))
                .setAutoCancel(true)
                .setShowWhen(true);
        Intent open = c.getPackageManager().getLaunchIntentForPackage(c.getPackageName());
        if (open != null) {
            open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
            b.setContentIntent(PendingIntent.getActivity(c, id, open, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE));
        }
        try {
            nm.notify(id, b.build());
        } catch (SecurityException ignored) {
            // 알림 허용을 거절했다
        }
    }
}
