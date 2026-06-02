import java.util.Locale
import org.gradle.api.tasks.Copy
import org.gradle.api.tasks.Exec

plugins {
  alias(libs.plugins.android.application)
  alias(libs.plugins.compose.compiler)
  alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.apkdv.clipdock"
    compileSdk = 36
    ndkVersion = "27.3.13750724"
    defaultConfig {
        applicationId = "com.apkdv.clipdock"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.7"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        ndk {
          abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
      compose = true
      aidl = false
      buildConfig = false
      shaders = false
    }

    packaging {
      resources {
        excludes += "/META-INF/{AL2.0,LGPL2.1}"
      }
    }

    sourceSets {
      getByName("main") {
        jniLibs.setSrcDirs(listOf(layout.buildDirectory.dir("generated/rustJniLibs").get().asFile))
      }
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
  val composeBom = platform(libs.androidx.compose.bom)
  implementation(composeBom)
  androidTestImplementation(composeBom)

  // Core Android dependencies
  implementation(libs.androidx.core.ktx)
  implementation(libs.androidx.lifecycle.runtime.ktx)
  implementation(libs.androidx.activity.compose)

  // Arch Components
  implementation(libs.androidx.lifecycle.runtime.compose)
  implementation(libs.androidx.lifecycle.viewmodel.compose)

  // Compose
  implementation(libs.androidx.compose.ui)
  implementation(libs.androidx.compose.ui.tooling.preview)
  implementation(libs.androidx.compose.material3)
  // Tooling
  debugImplementation(libs.androidx.compose.ui.tooling)
  // Instrumented tests
  androidTestImplementation(libs.androidx.compose.ui.test.junit4)
  debugImplementation(libs.androidx.compose.ui.test.manifest)

  // Local tests: jUnit, coroutines, Android runner
  testImplementation(libs.junit)
  testImplementation(libs.kotlinx.coroutines.test)
  testImplementation("org.json:json:20180813")

  // Instrumented tests: jUnit rules and runners
  androidTestImplementation(libs.androidx.test.core)
  androidTestImplementation(libs.androidx.test.ext.junit)
  androidTestImplementation(libs.androidx.test.runner)
  androidTestImplementation(libs.androidx.test.espresso.core)

  // Navigation
  implementation(libs.androidx.navigation3.ui)
  implementation(libs.androidx.navigation3.runtime)
  implementation(libs.androidx.lifecycle.viewmodel.navigation3)
}

data class RustAndroidTarget(
  val suffix: String,
  val triple: String,
  val abi: String,
  val clangPrefix: String,
)

val rustAndroidTargets =
  listOf(
    RustAndroidTarget("Arm64", "aarch64-linux-android", "arm64-v8a", "aarch64-linux-android"),
    RustAndroidTarget("X86_64", "x86_64-linux-android", "x86_64", "x86_64-linux-android"),
  )

val androidSdkDir =
  providers.environmentVariable("ANDROID_HOME").orElse("${System.getProperty("user.home")}/Library/Android/sdk")
val rustCrateDir = rootProject.file("rust/clipdock_p2p_jni")
val ndkToolchainDir =
  androidSdkDir.map { "$it/ndk/27.3.13750724/toolchains/llvm/prebuilt/darwin-x86_64/bin" }

val copyRustJniTasks =
  rustAndroidTargets.map { target ->
    val cargoBuild =
      tasks.register<Exec>("cargoBuildP2p${target.suffix}") {
        workingDir = rustCrateDir
        inputs.file(rustCrateDir.resolve("Cargo.toml"))
        inputs.file(rustCrateDir.resolve("Cargo.lock"))
        inputs.dir(rustCrateDir.resolve("src"))
        outputs.file(rustCrateDir.resolve("target/${target.triple}/debug/libclipdock_p2p_jni.so"))
        val upperTargetKey = target.triple.uppercase(Locale.US).replace("-", "_")
        val lowerTargetKey = target.triple.replace("-", "_")
        val clang = "${ndkToolchainDir.get()}/${target.clangPrefix}26-clang"
        val ar = "${ndkToolchainDir.get()}/llvm-ar"
        environment("CC_$upperTargetKey", clang)
        environment("AR_$upperTargetKey", ar)
        environment("CC_$lowerTargetKey", clang)
        environment("AR_$lowerTargetKey", ar)
        environment("CARGO_TARGET_${upperTargetKey}_LINKER", clang)
        commandLine("cargo", "build", "--target", target.triple)
      }

    tasks.register<Copy>("copyP2pJni${target.suffix}") {
      dependsOn(cargoBuild)
      from(rustCrateDir.resolve("target/${target.triple}/debug/libclipdock_p2p_jni.so"))
      into(layout.buildDirectory.dir("generated/rustJniLibs/${target.abi}"))
    }
  }

tasks.named("preBuild") {
  dependsOn(copyRustJniTasks)
}
