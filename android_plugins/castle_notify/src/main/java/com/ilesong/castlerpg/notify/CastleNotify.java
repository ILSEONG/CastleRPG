package com.ilesong.castlerpg.notify;

import android.Manifest;
import android.app.Activity;
import android.app.NotificationManager;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

/**
 * Godot 싱글턴 "CastleNotify"(scripts/notify.gd가 쓴다). 게임이 백그라운드로 갈 때 알림을 예약하고, 돌아오면 모두 지운다.
 * 알림은 AlarmManager(정확하지 않은 알람 — 권한 없이 몇 분 늦을 수 있다)로 시각에 NotifyReceiver를 깨워 띄운다.
 */
public class CastleNotify extends GodotPlugin {
    private static final int PERMISSION_REQUEST = 7301;

    public CastleNotify(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "CastleNotify";
    }

    private Context context() {
        Activity a = getActivity();
        return a != null ? a.getApplicationContext() : null;
    }

    /** 알림을 띄울 수 있다(Android 13 미만은 늘 허용, 앱 알림이 꺼져 있으면 false). */
    @UsedByGodot
    public boolean has_permission() {
        Context c = context();
        if (c == null) {
            return false;
        }
        if (Build.VERSION.SDK_INT >= 33
                && c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            return false;
        }
        NotificationManager nm = c.getSystemService(NotificationManager.class);
        return nm == null || nm.areNotificationsEnabled();
    }

    /** Android 13+ 알림 허용 창을 띄운다(이미 허용이면 아무것도 안 한다). */
    @UsedByGodot
    public void request_permission() {
        Activity a = getActivity();
        if (a == null || Build.VERSION.SDK_INT < 33) {
            return;
        }
        if (a.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            a.runOnUiThread(() -> a.requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, PERMISSION_REQUEST));
        }
    }

    /** 이 앱의 시스템 알림 설정 화면(허용을 거절한 뒤 다시 켤 때). */
    @UsedByGodot
    public void open_settings() {
        Activity a = getActivity();
        if (a == null) {
            return;
        }
        Intent i;
        if (Build.VERSION.SDK_INT >= 26) {
            i = new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS);
            i.putExtra(Settings.EXTRA_APP_PACKAGE, a.getPackageName());
        } else {
            i = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + a.getPackageName()));
        }
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            a.startActivity(i);
        } catch (Exception ignored) {
        }
    }

    /** delaySec초 뒤 알림 하나(같은 id는 덮어쓴다). */
    @UsedByGodot
    public void schedule(int id, String title, String body, int delaySec) {
        Context c = context();
        if (c == null) {
            return;
        }
        long at = System.currentTimeMillis() + Math.max(1, delaySec) * 1000L;
        Store.put(c, id, title, body, at);
        Alarms.set(c, id, title, body, at);
    }

    /** 예약한 알림을 모두 취소한다. */
    @UsedByGodot
    public void cancel_all() {
        Context c = context();
        if (c == null) {
            return;
        }
        for (int id : Store.ids(c)) {
            Alarms.cancel(c, id);
        }
        Store.clear(c);
    }

    /** 이미 떠 있는 이 게임의 알림을 지운다(게임에 돌아왔을 때). */
    @UsedByGodot
    public void clear_shown() {
        Context c = context();
        if (c == null) {
            return;
        }
        NotificationManager nm = c.getSystemService(NotificationManager.class);
        if (nm != null) {
            nm.cancelAll();
        }
    }
}
