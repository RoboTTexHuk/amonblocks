import 'dart:convert';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart'
    show AppTrackingTransparency, TrackingStatus;
import 'package:appsflyer_sdk/appsflyer_sdk.dart'
    show AppsFlyerOptions, AppsflyerSdk;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:timezone/data/latest.dart' as tzData;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_circular_progress_indicator/flutter_circular_progress_indicator.dart';

final List<String> adBlockFilters = [
  ".*.doubleclick.net/.*",
  ".*.ads.pubmatic.com/.*",
  ".*.googlesyndication.com/.*",
  ".*.google-analytics.com/.*",
  ".*.adservice.google.*/.*",
  ".*.adbrite.com/.*",
  ".*.exponential.com/.*",
  ".*.quantserve.com/.*",
  ".*.scorecardresearch.com/.*",
  ".*.zedo.com/.*",
  ".*.adsafeprotected.com/.*",
  ".*.teads.tv/.*",
  ".*.outbrain.com/.*",
];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  tzData.initializeTimeZones();

  runApp(const MaterialApp(home: FCMTokenInitPage()));
}

// FCM Background Handler
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  print("BG Message: ${message.messageId}");
  print("BG Data: ${message.data}");
}

class FCMTokenInitPage extends StatefulWidget {
  const FCMTokenInitPage({super.key});
  @override
  State<FCMTokenInitPage> createState() => _FCMTokenInitPageState();
}

class _FCMTokenInitPageState extends State<FCMTokenInitPage> {
  String? _fcmToken;

  @override
  void initState() {
    super.initState();

    FCMTokenChannel.listen((token) {
      setState(() => _fcmToken = token);
      print('FCM Token received: $token');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => MainWebViewPage(fcmToken: token)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class FCMTokenChannel {
  static const MethodChannel _channel = MethodChannel('com.example.fcm/token');
  static void listen(Function(String token) onToken) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'setToken') {
        final String token = call.arguments as String;
        onToken(token);
      }
    });
  }
}

class MainWebViewPage extends StatefulWidget {
  final String? fcmToken;
  const MainWebViewPage({super.key, required this.fcmToken});
  @override
  State<MainWebViewPage> createState() => _MainWebViewPageState();
}

class _MainWebViewPageState extends State<MainWebViewPage> {
  late InAppWebViewController webViewController;
  bool isLoading = false;
  final List<ContentBlocker> contentBlockers = [];
  final String mainUrl = "https://api.oneontherace.autos/";

  // Device & App Info
  String? deviceId;
  String? instanceId = "d67f89a0-1234-5678-9abc-def012345678";
  String? platformType;
  String? osVersion;
  String? appVersion;
  String? deviceLanguage;
  String? deviceTimezone;
  bool pushEnabled = true;

  // AppsFlyer
  AppsflyerSdk? appsFlyerSdk;
  String appsFlyerId = "";
  String conversionData = "";

  @override
  void initState() {
    super.initState();

    _initContentBlockers();
    _initFirebaseListeners();
    _initAppTrackingTransparency();
    _initAppsFlyer();
    _setupPushNotificationChannel();
    _initDeviceData();
    _initFirebaseMessaging();

    // Повторная инициализация ATT через 2 сек
    Future.delayed(const Duration(seconds: 2), _initAppTrackingTransparency);
    // Передача device/app данных в web через 6 сек
    Future.delayed(const Duration(seconds: 6), () {
      _sendDataToWeb();
      _sendRawDataToWeb();
    });
  }

  void _initContentBlockers() {
    for (final filter in adBlockFilters) {
      contentBlockers.add(ContentBlocker(
          trigger: ContentBlockerTrigger(urlFilter: filter),
          action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK)));
    }
    contentBlockers.add(ContentBlocker(
      trigger: ContentBlockerTrigger(urlFilter: ".cookie", resourceType: [
        ContentBlockerTriggerResourceType.RAW
      ]),
      action: ContentBlockerAction(
          type: ContentBlockerActionType.BLOCK, selector: ".notification"),
    ));
    contentBlockers.add(ContentBlocker(
      trigger: ContentBlockerTrigger(urlFilter: ".cookie", resourceType: [
        ContentBlockerTriggerResourceType.RAW
      ]),
      action: ContentBlockerAction(
          type: ContentBlockerActionType.CSS_DISPLAY_NONE,
          selector: ".privacy-info"),
    ));
    contentBlockers.add(ContentBlocker(
        trigger: ContentBlockerTrigger(urlFilter: ".*"),
        action: ContentBlockerAction(
            type: ContentBlockerActionType.CSS_DISPLAY_NONE,
            selector: ".banner, .banners, .ads, .ad, .advert")));
  }

  void _initFirebaseListeners() {
    FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      final uri = msg.data['uri'];
      if (uri != null) {
        _loadUrl(uri.toString());
      } else {
        _reloadMainUrl();
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage msg) {
      final uri = msg.data['uri'];
      if (uri != null) {
        _loadUrl(uri.toString());
      } else {
        _reloadMainUrl();
      }
    });
  }

  void _setupPushNotificationChannel() {
    MethodChannel('com.example.fcm/notification')
        .setMethodCallHandler((call) async {
      if (call.method == "onNotificationTap") {
        final Map<String, dynamic> data =
        Map<String, dynamic>.from(call.arguments);
        final url = data["uri"];
        if (url != null && !url.contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => PushUrlWebViewPage(url: url)),
                (route) => false,
          );
        }
      }
    });
  }

  Future<void> _initFirebaseMessaging() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
  }

  Future<void> _initAppTrackingTransparency() async {
    final status = await AppTrackingTransparency.trackingAuthorizationStatus;
    if (status == TrackingStatus.notDetermined) {
      await Future.delayed(const Duration(milliseconds: 1000));
      await AppTrackingTransparency.requestTrackingAuthorization();
    }
    final uuid = await AppTrackingTransparency.getAdvertisingIdentifier();
    print("ATT AdvertisingIdentifier: $uuid");
  }

  void _initAppsFlyer() {
    final options = AppsFlyerOptions(
      afDevKey: "qsBLmy7dAXDQhowM8V3ca4",
      appId: "6739503199",
      showDebug: true,
    );
    appsFlyerSdk = AppsflyerSdk(options);
    appsFlyerSdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );
    appsFlyerSdk?.startSDK(
      onSuccess: () => print("AppsFlyer started"),
      onError: (int code, String msg) => print("AppsFlyer error $code $msg"),
    );
    appsFlyerSdk?.onInstallConversionData((res) {
      setState(() {
        conversionData = res.toString();
        appsFlyerId = res['payload']['af_status'].toString();
      });
    });
    appsFlyerSdk?.getAppsFlyerUID().then((value) {
      setState(() {
        appsFlyerId = value.toString();
      });
    });
  }

  Future<void> _initDeviceData() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        deviceId = info.id;
        platformType = "android";
        osVersion = info.version.release;
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        deviceId = info.identifierForVendor;
        platformType = "ios";
        osVersion = info.systemVersion;
      }
      final packageInfo = await PackageInfo.fromPlatform();
      appVersion = packageInfo.version;
      deviceLanguage = Platform.localeName.split('_')[0];
      deviceTimezone = tz.local.name;
      if (webViewController != null) {
        _sendDataToWeb();
      }
    } catch (e) {
      debugPrint("Device data init error: $e");
    }
  }

  void _loadUrl(String uri) async {
    if (webViewController != null) {
      await webViewController.loadUrl(
        urlRequest: URLRequest(url: WebUri(uri)),
      );
    }
  }

  void _reloadMainUrl() async {
    Future.delayed(const Duration(seconds: 3), () {
      if (webViewController != null) {
        webViewController.loadUrl(
          urlRequest: URLRequest(url: WebUri(mainUrl)),
        );
      }
    });
  }

  Future<void> _sendDataToWeb() async {
    setState(() => isLoading = true);
    try {
      await webViewController.evaluateJavascript(source: '''
      localStorage.setItem('app_data', JSON.stringify({
        "fcm_token": "${widget.fcmToken ?? 'default_fcm_token'}",
        "device_id": "${deviceId ?? 'default_device_id'}",
        "app_name": "Jet4Betv1",
        "instance_id": "${instanceId ?? 'default_instance_id'}",
        "platform": "${platformType ?? 'unknown_platform'}",
        "os_version": "${osVersion ?? 'default_os_version'}",
        "app_version": "${appVersion ?? 'default_app_version'}",
        "language": "${deviceLanguage ?? 'en'}",
        "timezone": "${deviceTimezone ?? 'UTC'}",
        "push_enabled": $pushEnabled
      }));
      ''');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _sendRawDataToWeb() async {
    final data = {
      "content": {
        "af_data": "$conversionData",
        "af_id": "$appsFlyerId",
        "fb_app_name": "amonblocks",
        "app_name": "amonblocks",
        "deep": null,
        "bundle_identifier": "amonblock.amonblock.amonblock.amonblock",
        "app_version": "1.0.0",
        "apple_id": "6739503199",
        "fcm_token": widget.fcmToken ?? "default_fcm_token",
        "device_id": deviceId ?? "default_device_id",
        "instance_id": instanceId ?? "default_instance_id",
        "platform": platformType ?? "unknown_platform",
        "os_version": osVersion ?? "default_os_version",
        "app_version": appVersion ?? "default_app_version",
        "language": deviceLanguage ?? "en",
        "timezone": deviceTimezone ?? "UTC",
        "push_enabled": pushEnabled,
        "useruid": "$appsFlyerId",
      },
    };
    final jsonString = jsonEncode(data);
    print("SendRawData: $jsonString");

    print(" loadmyURL "+jsonString.toString());
    await webViewController.evaluateJavascript(
      source: "sendRawData(${jsonEncode(jsonString)});",
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          InAppWebView(
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              disableDefaultErrorPage: true,
              contentBlockers: contentBlockers,
              javaScriptCanOpenWindowsAutomatically: true,
            ),
            initialUrlRequest: URLRequest(url: WebUri(mainUrl)),
            onWebViewCreated: (controller) {
              webViewController = controller;
              webViewController.addJavaScriptHandler(
                handlerName: 'onServerResponse',
                callback: (args) {
                  print("JS args: $args");
                  return args.reduce((curr, next) => curr + next);
                },
              );
            },
            onLoadStart: (controller, url) {
              setState(() => isLoading = true);
            },
            onLoadStop: (controller, url) async {
              await controller.evaluateJavascript(
                source: "console.log('Hello from JS!');",
              );
              await _sendDataToWeb();
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              return NavigationActionPolicy.ALLOW;
            },
          ),
          if (isLoading)
            Center(
              child: CircularProgressInd().normalCircular(
                height: 80,
                width: 80,
                isSpining: true,
                valueColor: Colors.deepPurple,
                secondaryColor: Colors.grey,
                secondaryWidth: 10,
                valueWidth: 5,
              ),
            ),
        ],
      ),
    );
  }
}

class PushUrlWebViewPage extends StatefulWidget {
  final String url;
  const PushUrlWebViewPage({required this.url, super.key});
  @override
  State<PushUrlWebViewPage> createState() => _PushUrlWebViewPageState();
}

class _PushUrlWebViewPageState extends State<PushUrlWebViewPage> {
  late InAppWebViewController webViewController;
  double loadingProgress = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          InAppWebView(
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              javaScriptCanOpenWindowsAutomatically: true,
            ),
            initialUrlRequest: URLRequest(url: WebUri(widget.url)),
            onWebViewCreated: (controller) {
              webViewController = controller;
            },
            onLoadStart: (controller, url) {
              setState(() => loadingProgress = 0);
            },
            onLoadStop: (controller, url) {
              setState(() => loadingProgress = 1);
            },
            onProgressChanged: (controller, progress) {
              setState(() => loadingProgress = progress / 100);
            },
          ),
          if (loadingProgress < 1)
            LinearProgressIndicator(
              value: loadingProgress,
              backgroundColor: Colors.grey[200],
              color: Colors.blue,
            ),
        ],
      ),
    );
  }
}