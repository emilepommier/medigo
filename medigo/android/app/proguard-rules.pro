# Keep ONNX Runtime Java API classes accessed via reflection
-keep class ai.onnxruntime.** { *; }
-keep class com.microsoft.onnxruntime.** { *; }
-keep class ai.onnxruntime.extensions.** { *; }

# Prevent obfuscation of enum names and annotations often reflected upon
-keepclassmembers enum * { public static **[] values(); public static ** valueOf(java.lang.String); }
-keepattributes *Annotation*,InnerClasses,EnclosingMethod,Signature

# Keep Kotlin metadata used by reflection in some libs
-keep class kotlin.Metadata { *; }

# Flutter embedding keeps
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# Do not warn on onnx packages to reduce noise
-dontwarn ai.onnxruntime.**
-dontwarn com.microsoft.onnxruntime.**
