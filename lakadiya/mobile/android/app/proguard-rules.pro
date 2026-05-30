# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Razorpay
-keepclassmembers class com.razorpay.** { *; }
-keep class com.razorpay.** { *; }
-dontwarn com.razorpay.**
-optimizations !method/inlining/*

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**

# OkHttp / Dio networking
-dontwarn okhttp3.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# SMS autofill
-keep class com.truecaller.android.sdkuikit.** { *; }

# Prevent stripping enums used via reflection
-keepclassmembers enum * { *; }

# Hive local storage
-keep class com.hivedb.** { *; }
