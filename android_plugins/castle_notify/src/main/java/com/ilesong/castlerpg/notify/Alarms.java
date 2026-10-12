package com.ilesong.castlerpg.notify;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;

/** AlarmManager 예약·취소. 같은 id(requestCode)는 같은 알람 하나다. */
final class Alarms {
    static final String EXTRA_ID = "castle_notify_id";
    static final String EXTRA_TITLE = "castle_notify_title";
    static final String EXTRA_BODY = "castle_notify_body";

    private Alarms() {
    }

    private static Intent intent(Context c) {
        return new Intent(c, NotifyReceiver.class);
    }

    static void set(Context c, int id, String title, String body, long atMillis) {
        AlarmManager am = c.getSystemService(AlarmManager.class);
        if (am == null) {
            return;
        }
        Intent i = intent(c);
        i.putExtra(EXTRA_ID, id);
        i.putExtra(EXTRA_TITLE, title);
        i.putExtra(EXTRA_BODY, body);
        PendingIntent pi = PendingIntent.getBroadcast(c, id, i, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        // 정확한 알람 권한(SCHEDULE_EXACT_ALARM) 없이 쓰는 방식 — 절전 중에도 울리지만 몇 분 늦을 수 있다.
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pi);
    }

    static void cancel(Context c, int id) {
        AlarmManager am = c.getSystemService(AlarmManager.class);
        PendingIntent pi = PendingIntent.getBroadcast(c, id, intent(c), PendingIntent.FLAG_NO_CREATE | PendingIntent.FLAG_IMMUTABLE);
        if (am != null && pi != null) {
            am.cancel(pi);
            pi.cancel();
        }
    }
}
