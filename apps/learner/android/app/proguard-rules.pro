# google_mlkit_text_recognition compiles optional non-Latin recognizers as
# compileOnly dependencies. VerbaSeed ships the Latin recognizer only, so R8
# must not treat those intentionally absent script modules as missing runtime
# classes. Add the corresponding ML Kit artifacts instead of removing these
# rules if those scripts are enabled later.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
