import 'dart:js_interop';

import 'package:flutter/foundation.dart';

// [attribute] should be just "lang"
@JS('document.documentElement.setAttribute')
external void setLang(JSString? attribute, JSString? lang);

void setBrowserLang(String languageCode) {
  if (!kIsWeb) return;

  setLang('lang'.toJS, languageCode.toJS);
}
