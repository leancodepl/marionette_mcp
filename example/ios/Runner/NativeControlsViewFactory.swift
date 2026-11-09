import Flutter
import UIKit

private let channelName = "marionette_example/native_controls"

class NativeControlsViewFactory: NSObject, FlutterPlatformViewFactory {
  private var messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    return NativeControlsPlatformView(frame: frame, messenger: messenger)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

class NativeControlsPlatformView: NSObject, FlutterPlatformView {
  private let stackView: UIStackView
  private let channel: FlutterMethodChannel

  init(frame: CGRect, messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)

    stackView = UIStackView(frame: frame)
    stackView.axis = .vertical
    stackView.spacing = 12
    stackView.alignment = .fill
    stackView.distribution = .fill
    stackView.backgroundColor = UIColor(red: 0.91, green: 0.96, blue: 0.91, alpha: 1)
    stackView.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    stackView.isLayoutMarginsRelativeArrangement = true

    let label = UILabel()
    label.text = "Native label"
    label.accessibilityIdentifier = "native_label"
    stackView.addArrangedSubview(label)

    let field = UITextField()
    field.placeholder = "Type here (native)"
    field.borderStyle = .roundedRect
    field.accessibilityIdentifier = "native_input"
    stackView.addArrangedSubview(field)

    let button = UIButton(type: .system)
    button.setTitle("Tap me (native)", for: .normal)
    button.accessibilityIdentifier = "native_button"
    stackView.addArrangedSubview(button)

    super.init()

    button.addTarget(self, action: #selector(nativeButtonTapped), for: .touchUpInside)
  }

  @objc private func nativeButtonTapped() {
    channel.invokeMethod("nativeButtonTapped", arguments: nil)
  }

  func view() -> UIView {
    return stackView
  }
}
