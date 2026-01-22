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
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Fix for older Flutter plugins that don't have namespace defined
subprojects {
    afterEvaluate {
        if (project.plugins.hasPlugin("com.android.library")) {
            project.extensions.findByType<com.android.build.gradle.LibraryExtension>()?.apply {
                if (namespace == null) {
                    namespace = project.group.toString().ifEmpty { "io.github.nickcats.flutter_app_badger" }
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
