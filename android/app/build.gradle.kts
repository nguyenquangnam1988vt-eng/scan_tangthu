android {
    namespace "com.example.ho_so_scanner"
    compileSdk 34
    defaultConfig {
        applicationId "com.example.ho_so_scanner"
        minSdk 21
        targetSdk 34
        versionCode 1
        versionName "1.0.0"
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = '17' }
}