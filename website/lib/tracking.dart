/// LeanCode's marketing analytics: the CookieScript consent banner and the
/// Google Tag Manager container, which holds the GA4 tag.
library;

import 'package:jaspr/dom.dart';

// Both IDs are public by design: they ship in the HTML of every page.
const _cookieScriptSrc =
    'https://cdn.cookie-script.com/s/3aee4f412722d00911596bace9d15935.js';
const _gtmId = 'GTM-KS95JFHZ';

/// Google's standard container loader.
const _gtmLoader =
    "(function(w,d,s,l,i){w[l]=w[l]||[];w[l].push({'gtm.start':"
    "new Date().getTime(),event:'gtm.js'});var f=d.getElementsByTagName(s)[0],"
    "j=d.createElement(s),dl=l!='dataLayer'?'&l='+l:'';j.async=true;j.src="
    "'https://www.googletagmanager.com/gtm.js?id='+i+dl;"
    'f.parentNode.insertBefore(j,f);})'
    "(window,document,'script','dataLayer','$_gtmId');";

/// The first `<head>` children of every production page. The banner loads
/// before the container and blocks parsing until it runs: its Google Consent
/// Mode integration, a setting in the CookieScript panel, is what holds the
/// Google tags back until the visitor consents.
const trackingHead = [
  script(src: _cookieScriptSrc, attributes: {'charset': 'UTF-8'}),
  script(content: _gtmLoader),
];
