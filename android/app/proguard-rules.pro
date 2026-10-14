# ML Kit: pack bahasa optional yang tak dipakai (kita guna Latin je)
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# TFLite: GPU delegate tak disertakan
-dontwarn org.tensorflow.lite.gpu.**

# Jangan buang class TFLite (dipanggil dari native code)
-keep class org.tensorflow.lite.** { *; }