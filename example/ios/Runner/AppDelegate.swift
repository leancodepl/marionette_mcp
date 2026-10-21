import Flutter
import GoogleMaps
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_API_KEY") as? String,
       !apiKey.isEmpty {
      GMSServices.provideAPIKey(apiKey)
    }
    // flutter_local_notifications: deliver notification taps to the plugin.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let factory = NativeControlsViewFactory(
      messenger: engineBridge.applicationRegistrar.messenger()
    )
    engineBridge.applicationRegistrar.register(
      factory,
      withId: "marionette-demo-native-controls"
    )

    // Native UI that the native lane must handle on its own.
    let channel = FlutterMethodChannel(
      name: "marionette-demo/native",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "showAlert":
        let alert = UIAlertController(
          title: args["title"] as? String,
          message: args["message"] as? String,
          preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in result("cancel") })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in result("ok") })
        Self.topViewController()?.present(alert, animated: true)
      case "showToast":
        result(FlutterError(code: "unsupported", message: "Toasts exist only on Android", details: nil))
      case "openNativeScreen":
        let screen = NativeFormViewController { text in result(text) }
        let navigation = UINavigationController(rootViewController: screen)
        navigation.modalPresentationStyle = .fullScreen
        Self.topViewController()?.present(navigation, animated: true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// The view controller currently on top, to present native UI over Flutter.
  static func topViewController() -> UIViewController? {
    let window = UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow }
      .first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}

/// A full native screen outside Flutter. Returns the typed text to the
/// Flutter screen that opened it.
final class NativeFormViewController: UIViewController {
  private let onDone: (String) -> Void
  private let field = UITextField()

  init(onDone: @escaping (String) -> Void) {
    self.onDone = onDone
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { nil }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Native screen"
    view.backgroundColor = .systemBackground

    field.placeholder = "Native name"
    field.accessibilityIdentifier = "native_form_name"
    field.borderStyle = .roundedRect

    let back = UIButton(type: .system)
    back.setTitle("Back to Flutter", for: .normal)
    back.accessibilityIdentifier = "native_form_back"
    back.addAction(UIAction { [weak self] _ in self?.finish() }, for: .touchUpInside)

    let stack = UIStackView(arrangedSubviews: [field, back])
    stack.axis = .vertical
    stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
    ])
  }

  private func finish() {
    let text = field.text ?? ""
    dismiss(animated: true) { [onDone] in onDone(text) }
  }
}
