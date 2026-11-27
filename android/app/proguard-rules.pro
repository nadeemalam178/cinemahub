# Keep libtorrent4j SWIG JNI bindings intact under R8/ProGuard
-keep class org.libtorrent4j.swig.** { *; }
-dontwarn org.libtorrent4j.**
