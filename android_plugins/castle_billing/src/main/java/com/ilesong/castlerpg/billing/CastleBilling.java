package com.ilesong.castlerpg.billing;

import android.app.Activity;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.android.billingclient.api.BillingClient;
import com.android.billingclient.api.BillingClientStateListener;
import com.android.billingclient.api.BillingFlowParams;
import com.android.billingclient.api.BillingResult;
import com.android.billingclient.api.PendingPurchasesParams;
import com.android.billingclient.api.ProductDetails;
import com.android.billingclient.api.Purchase;
import com.android.billingclient.api.PurchasesUpdatedListener;
import com.android.billingclient.api.QueryProductDetailsParams;
import com.android.billingclient.api.QueryPurchasesParams;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Set;
import java.util.HashSet;

/**
 * Google Play 결제(Play Billing Library 8.x)를 GDScript 에 노출하는 Godot 플러그인(v2).
 * GDScript: Engine.get_singleton("CastleBilling")
 *
 * 클라이언트는 구매를 확인(acknowledge)하거나 소비(consume)하지 않는다 —
 * 구매 토큰을 서버로 보내면 서버가 지급한 뒤 소비한다.
 * 어떤 오류도 앱을 죽이지 않도록 모든 진입점을 감싼다.
 */
public class CastleBilling extends GodotPlugin implements PurchasesUpdatedListener {
    private static final String TAG = "CastleBilling";

    private static final String SIGNAL_CONNECTED = "connected";
    private static final String SIGNAL_PURCHASE_TOKEN = "purchase_token";
    private static final String SIGNAL_PURCHASE_ERROR = "purchase_error";
    private static final String SIGNAL_PURCHASES_QUERIED = "purchases_queried";

    /** 연결이 끝난 뒤(성공/실패) 실행할 작업. */
    private interface ReadyAction {
        void run(BillingResult result);
    }

    private final Object lock = new Object();
    @Nullable private BillingClient client;
    private boolean connecting = false;
    private final List<ReadyAction> pending = new ArrayList<>();

    public CastleBilling(Godot godot) {
        super(godot);
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "CastleBilling";
    }

    @NonNull
    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(new SignalInfo(SIGNAL_CONNECTED, Boolean.class));
        signals.add(new SignalInfo(SIGNAL_PURCHASE_TOKEN, String.class, String.class, Integer.class));
        signals.add(new SignalInfo(SIGNAL_PURCHASE_ERROR, Integer.class, String.class));
        signals.add(new SignalInfo(SIGNAL_PURCHASES_QUERIED, Integer.class));
        return signals;
    }

    // ---------------------------------------------------------------- GDScript API

    /** 결제 서비스에 연결한다. 결과는 connected(ok). 여러 번 불러도 안전하다. */
    @UsedByGodot
    public void startConnection() {
        try {
            whenReady(result -> emitSafe(SIGNAL_CONNECTED, result.getResponseCode() == BillingClient.BillingResponseCode.OK));
        } catch (Throwable t) {
            Log.e(TAG, "startConnection failed", t);
            emitSafe(SIGNAL_CONNECTED, false);
        }
    }

    /** 일회성(INAPP) 상품 구매 흐름을 띄운다. accountTag 는 obfuscatedAccountId 로 들어간다. */
    @UsedByGodot
    public void purchase(final String productId, final String accountTag) {
        try {
            whenReady(result -> {
                if (result.getResponseCode() != BillingClient.BillingResponseCode.OK) {
                    emitError(result.getResponseCode(), "billing not ready: " + result.getDebugMessage());
                    return;
                }
                queryAndLaunch(productId, accountTag);
            });
        } catch (Throwable t) {
            Log.e(TAG, "purchase failed", t);
            emitError(BillingClient.BillingResponseCode.DEVELOPER_ERROR, "purchase failed: " + t);
        }
    }

    /** 가지고 있는(아직 소비되지 않은) 구매를 모두 purchase_token 으로 다시 보낸다. 끝나면 purchases_queried(count). */
    @UsedByGodot
    public void queryPurchases() {
        try {
            whenReady(result -> {
                if (result.getResponseCode() != BillingClient.BillingResponseCode.OK) {
                    Log.w(TAG, "queryPurchases: billing not ready " + result.getResponseCode());
                    emitSafe(SIGNAL_PURCHASES_QUERIED, 0);
                    return;
                }
                BillingClient c = currentClient();
                if (c == null) {
                    emitSafe(SIGNAL_PURCHASES_QUERIED, 0);
                    return;
                }
                QueryPurchasesParams params = QueryPurchasesParams.newBuilder()
                        .setProductType(BillingClient.ProductType.INAPP)
                        .build();
                c.queryPurchasesAsync(params, (billingResult, purchases) -> {
                    try {
                        if (billingResult.getResponseCode() != BillingClient.BillingResponseCode.OK || purchases == null) {
                            Log.w(TAG, "queryPurchasesAsync: " + billingResult.getResponseCode() + " " + billingResult.getDebugMessage());
                            emitSafe(SIGNAL_PURCHASES_QUERIED, 0);
                            return;
                        }
                        for (Purchase p : purchases) {
                            emitPurchase(p);
                        }
                        emitSafe(SIGNAL_PURCHASES_QUERIED, purchases.size());
                    } catch (Throwable t) {
                        Log.e(TAG, "queryPurchases callback failed", t);
                        emitSafe(SIGNAL_PURCHASES_QUERIED, 0);
                    }
                });
            });
        } catch (Throwable t) {
            Log.e(TAG, "queryPurchases failed", t);
            emitSafe(SIGNAL_PURCHASES_QUERIED, 0);
        }
    }

    // ---------------------------------------------------------------- 결제 라이브러리 콜백

    @Override
    public void onPurchasesUpdated(@NonNull BillingResult result, @Nullable List<Purchase> purchases) {
        try {
            int code = result.getResponseCode();
            if (code == BillingClient.BillingResponseCode.OK) {
                if (purchases != null) {
                    for (Purchase p : purchases) {
                        emitPurchase(p);
                    }
                }
                return;
            }
            emitError(code, result.getDebugMessage());
            if (code == BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED) {
                queryPurchases();
            }
        } catch (Throwable t) {
            Log.e(TAG, "onPurchasesUpdated failed", t);
        }
    }

    @Override
    public void onMainDestroy() {
        try {
            synchronized (lock) {
                if (client != null) {
                    client.endConnection();
                    client = null;
                }
                connecting = false;
                pending.clear();
            }
        } catch (Throwable t) {
            Log.e(TAG, "endConnection failed", t);
        }
        super.onMainDestroy();
    }

    // ---------------------------------------------------------------- 내부

    private void queryAndLaunch(final String productId, final String accountTag) {
        BillingClient c = currentClient();
        if (c == null) {
            emitError(BillingClient.BillingResponseCode.BILLING_UNAVAILABLE, "billing client missing");
            return;
        }
        QueryProductDetailsParams params = QueryProductDetailsParams.newBuilder()
                .setProductList(Collections.singletonList(
                        QueryProductDetailsParams.Product.newBuilder()
                                .setProductId(productId)
                                .setProductType(BillingClient.ProductType.INAPP)
                                .build()))
                .build();
        c.queryProductDetailsAsync(params, (billingResult, detailsResult) -> {
            try {
                if (billingResult.getResponseCode() != BillingClient.BillingResponseCode.OK) {
                    emitError(billingResult.getResponseCode(), "product query failed: " + billingResult.getDebugMessage());
                    return;
                }
                ProductDetails details = null;
                List<ProductDetails> list = detailsResult == null ? null : detailsResult.getProductDetailsList();
                if (list != null) {
                    for (ProductDetails d : list) {
                        if (productId.equals(d.getProductId())) {
                            details = d;
                            break;
                        }
                    }
                }
                if (details == null) {
                    emitError(BillingClient.BillingResponseCode.ITEM_UNAVAILABLE, "product not found: " + productId);
                    return;
                }
                launchFlow(details, accountTag);
            } catch (Throwable t) {
                Log.e(TAG, "product details callback failed", t);
                emitError(BillingClient.BillingResponseCode.DEVELOPER_ERROR, "product query failed: " + t);
            }
        });
    }

    private void launchFlow(final ProductDetails details, final String accountTag) {
        final Activity activity = getActivity();
        if (activity == null) {
            emitError(BillingClient.BillingResponseCode.DEVELOPER_ERROR, "no activity");
            return;
        }
        activity.runOnUiThread(() -> {
            try {
                BillingClient c = currentClient();
                if (c == null) {
                    emitError(BillingClient.BillingResponseCode.BILLING_UNAVAILABLE, "billing client missing");
                    return;
                }
                BillingFlowParams.ProductDetailsParams.Builder pdp = BillingFlowParams.ProductDetailsParams.newBuilder()
                        .setProductDetails(details);
                // 일회성 상품에 여러 구매 옵션/혜택이 있으면 첫 번째(기본) 혜택 토큰을 지정한다.
                try {
                    List<ProductDetails.OneTimePurchaseOfferDetails> offers = details.getOneTimePurchaseOfferDetailsList();
                    if (offers != null && !offers.isEmpty() && offers.get(0).getOfferToken() != null) {
                        pdp.setOfferToken(offers.get(0).getOfferToken());
                    }
                } catch (Throwable t) {
                    Log.w(TAG, "offer token lookup failed", t);
                }
                BillingFlowParams.Builder fb = BillingFlowParams.newBuilder()
                        .setProductDetailsParamsList(Collections.singletonList(pdp.build()));
                if (accountTag != null && !accountTag.isEmpty()) {
                    fb.setObfuscatedAccountId(accountTag);
                }
                BillingResult r = c.launchBillingFlow(activity, fb.build());
                int code = r.getResponseCode();
                if (code != BillingClient.BillingResponseCode.OK) {
                    emitError(code, "launchBillingFlow: " + r.getDebugMessage());
                    if (code == BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED) {
                        queryPurchases();
                    }
                }
            } catch (Throwable t) {
                Log.e(TAG, "launchBillingFlow failed", t);
                emitError(BillingClient.BillingResponseCode.DEVELOPER_ERROR, "launchBillingFlow failed: " + t);
            }
        });
    }

    @Nullable
    private BillingClient currentClient() {
        synchronized (lock) {
            return client;
        }
    }

    /** 연결되어 있으면 바로, 아니면 연결을 시작하고 끝난 뒤 action 을 실행한다. */
    private void whenReady(ReadyAction action) {
        BillingClient c;
        boolean ready = false;
        boolean start = false;
        synchronized (lock) {
            if (client == null) {
                try {
                    client = buildClient();
                } catch (Throwable t) {
                    Log.e(TAG, "BillingClient init failed", t);
                    client = null;
                }
            }
            c = client;
            if (c != null) {
                if (c.isReady()) {
                    ready = true;
                } else {
                    pending.add(action);
                    if (!connecting) {
                        connecting = true;
                        start = true;
                    }
                }
            }
        }
        if (c == null) {
            // 초기화 불가(Play 스토어 없음 등): 바로 실패로 끝낸다.
            action.run(BillingResult.newBuilder()
                    .setResponseCode(BillingClient.BillingResponseCode.BILLING_UNAVAILABLE)
                    .setDebugMessage("billing init failed")
                    .build());
            return;
        }
        if (ready) {
            action.run(BillingResult.newBuilder().setResponseCode(BillingClient.BillingResponseCode.OK).build());
            return;
        }
        if (start) {
            try {
                c.startConnection(new BillingClientStateListener() {
                    @Override
                    public void onBillingSetupFinished(@NonNull BillingResult result) {
                        flushPending(result);
                    }

                    @Override
                    public void onBillingServiceDisconnected() {
                        Log.w(TAG, "billing service disconnected");
                        flushPending(BillingResult.newBuilder()
                                .setResponseCode(BillingClient.BillingResponseCode.SERVICE_DISCONNECTED)
                                .setDebugMessage("service disconnected")
                                .build());
                    }
                });
            } catch (Throwable t) {
                Log.e(TAG, "startConnection threw", t);
                flushPending(BillingResult.newBuilder()
                        .setResponseCode(BillingClient.BillingResponseCode.BILLING_UNAVAILABLE)
                        .setDebugMessage("startConnection failed: " + t)
                        .build());
            }
        }
    }

    private void flushPending(BillingResult result) {
        List<ReadyAction> actions;
        synchronized (lock) {
            connecting = false;
            actions = new ArrayList<>(pending);
            pending.clear();
        }
        for (ReadyAction a : actions) {
            try {
                a.run(result);
            } catch (Throwable t) {
                Log.e(TAG, "pending action failed", t);
            }
        }
    }

    private BillingClient buildClient() {
        Activity activity = getActivity();
        if (activity == null) {
            throw new IllegalStateException("no activity");
        }
        BillingClient.Builder b = BillingClient.newBuilder(activity.getApplicationContext())
                .setListener(this)
                .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build());
        try {
            b.enableAutoServiceReconnection();
        } catch (Throwable t) {
            Log.w(TAG, "enableAutoServiceReconnection unavailable", t);
        }
        return b.build();
    }

    private void emitPurchase(Purchase p) {
        if (p == null) {
            return;
        }
        String token = p.getPurchaseToken();
        int state = p.getPurchaseState();
        List<String> products = p.getProducts();
        if (products == null) {
            return;
        }
        for (String productId : products) {
            emitSafe(SIGNAL_PURCHASE_TOKEN, productId, token, state);
        }
    }

    private void emitError(int code, String message) {
        emitSafe(SIGNAL_PURCHASE_ERROR, code, message == null ? "" : message);
    }

    private void emitSafe(String signal, Object... args) {
        try {
            emitSignal(signal, args);
        } catch (Throwable t) {
            Log.e(TAG, "emitSignal " + signal + " failed", t);
        }
    }
}
