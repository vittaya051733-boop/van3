allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    configurations.configureEach {
        resolutionStrategy.force(
            "org.jetbrains.kotlin:kotlin-stdlib:2.2.21",
            "org.jetbrains.kotlin:kotlin-stdlib-jdk7:2.2.21",
            "org.jetbrains.kotlin:kotlin-stdlib-jdk8:2.2.21",
            "com.google.maps.android:android-maps-utils:3.6.0",
        )
    }

    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    afterEvaluate {
        if (project.plugins.hasPlugin("com.android.library")) {
            extensions.configure<com.android.build.api.dsl.LibraryExtension>("android") {
                compileSdk = 36
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
