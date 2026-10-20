/// Client entrypoint: hydrates the `@client` islands on the pre-rendered page.
library;

import 'package:jaspr/client.dart';
import 'package:marionette_website/main.client.options.dart';

void main() {
  Jaspr.initializeApp(options: defaultClientOptions);
  runApp(const ClientApp());
}
