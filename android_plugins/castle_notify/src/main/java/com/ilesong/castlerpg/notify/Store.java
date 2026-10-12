package com.ilesong.castlerpg.notify;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/** 예약한 알림 기록(재부팅 뒤 BootReceiver가 다시 건다). SharedPreferences "castle_notify". */
final class Store {
    private static final String FILE = "castle_notify";
    private static final String IDS = "ids";

    private Store() {
    }

    private static SharedPreferences prefs(Context c) {
        return c.getSharedPreferences(FILE, Context.MODE_PRIVATE);
    }

    static List<Integer> ids(Context c) {
        List<Integer> out = new ArrayList<>();
        for (String s : prefs(c).getStringSet(IDS, new HashSet<>())) {
            try {
                out.add(Integer.parseInt(s));
            } catch (NumberFormatException ignored) {
            }
        }
        return out;
    }

    static void put(Context c, int id, String title, String body, long at) {
        Set<String> ids = new HashSet<>(prefs(c).getStringSet(IDS, new HashSet<>()));
        ids.add(Integer.toString(id));
        prefs(c).edit().putStringSet(IDS, ids).putString("t_" + id, title).putString("b_" + id, body).putLong("at_" + id, at).apply();
    }

    static void remove(Context c, int id) {
        Set<String> ids = new HashSet<>(prefs(c).getStringSet(IDS, new HashSet<>()));
        ids.remove(Integer.toString(id));
        prefs(c).edit().putStringSet(IDS, ids).remove("t_" + id).remove("b_" + id).remove("at_" + id).apply();
    }

    static void clear(Context c) {
        prefs(c).edit().clear().apply();
    }

    static String title(Context c, int id) {
        return prefs(c).getString("t_" + id, "");
    }

    static String body(Context c, int id) {
        return prefs(c).getString("b_" + id, "");
    }

    static long at(Context c, int id) {
        return prefs(c).getLong("at_" + id, 0L);
    }
}
