package com.ilesong.castlerpg.notify;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** 재부팅·앱 업데이트 뒤 남은 예약을 다시 건다(지난 것은 곧바로 띄운다). */
public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context c, Intent intent) {
        String action = intent.getAction();
        if (!Intent.ACTION_BOOT_COMPLETED.equals(action) && !Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)) {
            return;
        }
        long soon = System.currentTimeMillis() + 10_000L;
        for (int id : Store.ids(c)) {
            Alarms.set(c, id, Store.title(c, id), Store.body(c, id), Math.max(Store.at(c, id), soon));
        }
    }
}
