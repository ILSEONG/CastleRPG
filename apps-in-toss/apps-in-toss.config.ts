import { defineConfig } from '@apps-in-toss/web-framework/config'

// 앱인토스 콘솔에 등록한 앱 이름(appName)과 같아야 한다. 콘솔에서 다른 이름으로 만들었다면 여기만 바꾼다.
export default defineConfig({
  appName: 'castlerpg',
  brand: {
    primaryColor: '#F08A24',
  },
  navigationBar: {
    withBackButton: false,
    withHomeButton: false,
    withTitle: false,
    transparentBackground: true,
  },
  webView: {
    bounces: false,
    pullToRefreshEnabled: false,
    overScrollMode: 'never',
    allowsBackForwardNavigationGestures: false,
    mediaPlaybackRequiresUserAction: false,
  },
  permissions: [],
  webBundleDir: 'dist',
})
