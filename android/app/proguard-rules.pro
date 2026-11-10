# SQLCipher / sqlcipher-android
-keep class net.sqlcipher.** { *; }
-keep class net.zetetic.database.** { *; }
-dontwarn net.sqlcipher.**

# Flutter plugins that use reflection
-keep class io.flutter.** { *; }
-keep class com.hamrah.app.** { *; }
