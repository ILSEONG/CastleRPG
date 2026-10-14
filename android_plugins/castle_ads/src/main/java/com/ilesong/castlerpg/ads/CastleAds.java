package com.ilesong.castlerpg.ads;

import android.app.Activity;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.google.android.gms.ads.AdError;
import com.google.android.gms.ads.AdRequest;
import com.google.android.gms.ads.FullScreenContentCallback;
import com.google.android.gms.ads.LoadAdError;
import com.google.android.gms.ads.MobileAds;
import com.google.android.gms.ads.rewarded.RewardedAd;
import com.google.android.gms.ads.rewarded.RewardedAdLoadCallback;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.HashSet;
import java.util.Set;

/**
 * AdMob 보상형 광고를 GDScript 에 노출하는 Godot 플러그인(v2).
 * GDScript: Engine.get_singleton("CastleAds")
 *
 * 흐름: initialize() → load(unitId) → ad_loaded(ok, error) → show() → ad_closed(earned).
 * earned 는 사용자가 광고를 끝까지 봐서 보상 콜백이 온 경우에만 true.
 * 어떤 오류도 앱을 죽이지 않도록 모든 진입점을 감싼다.
 */
public class CastleAds extends GodotPlugin {
    private static final String TAG = "CastleAds";

    private static final String SIGNAL_LOADED = "ad_loaded";
    private static final String SIGNAL_CLOSED = "ad_closed";

    @Nullable private RewardedAd ad;
    private boolean loading = false;
    private boolean earned = false;
    private boolean showing = false;

    public CastleAds(Godot godot) {
        super(godot);
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "CastleAds";
    }

    @NonNull
    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(new SignalInfo(SIGNAL_LOADED, Boolean.class, String.class));
        signals.add(new SignalInfo(SIGNAL_CLOSED, Boolean.class));
        return signals;
    }

    // ---------------------------------------------------------------- GDScript API

    /** 광고 SDK를 초기화한다. 여러 번 불러도 안전하다. */
    @UsedByGodot
    public void initialize() {
        final Activity activity = getActivity();
        if (activity == null) return;
        new Thread(() -> {
            try {
                MobileAds.initialize(activity, status -> Log.i(TAG, "MobileAds ready"));
            } catch (Throwable t) {
                Log.e(TAG, "initialize failed", t);
            }
        }).start();
    }

    /** 보상형 광고를 미리 불러온다. 결과는 ad_loaded(ok, error). */
    @UsedByGodot
    public void load(final String unitId) {
        final Activity activity = getActivity();
        if (activity == null) {
            emitSignal(SIGNAL_LOADED, false, "no_activity");
            return;
        }
        activity.runOnUiThread(() -> {
            try {
                if (ad != null) {
                    emitSignal(SIGNAL_LOADED, true, "");
                    return;
                }
                if (loading) return;
                loading = true;
                RewardedAd.load(activity, unitId, new AdRequest.Builder().build(), new RewardedAdLoadCallback() {
                    @Override
                    public void onAdLoaded(@NonNull RewardedAd loaded) {
                        loading = false;
                        ad = loaded;
                        emitSignal(SIGNAL_LOADED, true, "");
                    }

                    @Override
                    public void onAdFailedToLoad(@NonNull LoadAdError error) {
                        loading = false;
                        ad = null;
                        Log.w(TAG, "load failed: " + error);
                        emitSignal(SIGNAL_LOADED, false, error.getCode() + ":" + error.getMessage());
                    }
                });
            } catch (Throwable t) {
                loading = false;
                Log.e(TAG, "load failed", t);
                emitSignal(SIGNAL_LOADED, false, String.valueOf(t.getMessage()));
            }
        });
    }

    /** 불러온 광고가 있는지. */
    @UsedByGodot
    public boolean isLoaded() {
        return ad != null;
    }

    /** 불러온 광고를 띄운다. 닫히면 ad_closed(earned). 광고가 없으면 곧바로 ad_closed(false). */
    @UsedByGodot
    public void show() {
        final Activity activity = getActivity();
        if (activity == null) {
            emitSignal(SIGNAL_CLOSED, false);
            return;
        }
        activity.runOnUiThread(() -> {
            try {
                final RewardedAd current = ad;
                if (current == null || showing) {
                    if (!showing) emitSignal(SIGNAL_CLOSED, false);
                    return;
                }
                ad = null;  // 한 광고는 한 번만 보여 줄 수 있다
                earned = false;
                showing = true;
                current.setFullScreenContentCallback(new FullScreenContentCallback() {
                    @Override
                    public void onAdDismissedFullScreenContent() {
                        showing = false;
                        emitSignal(SIGNAL_CLOSED, earned);
                    }

                    @Override
                    public void onAdFailedToShowFullScreenContent(@NonNull AdError error) {
                        showing = false;
                        Log.w(TAG, "show failed: " + error);
                        emitSignal(SIGNAL_CLOSED, false);
                    }
                });
                current.show(activity, reward -> earned = true);
            } catch (Throwable t) {
                showing = false;
                Log.e(TAG, "show failed", t);
                emitSignal(SIGNAL_CLOSED, false);
            }
        });
    }
}
