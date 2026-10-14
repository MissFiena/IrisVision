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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

subprojects {
    val fixNamespace = {
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {
            try {
                val getNamespace = androidExt.javaClass.methods.find { it.name == "getNamespace" }
                val setNamespace = androidExt.javaClass.methods.find { it.name == "setNamespace" }
                if (getNamespace != null && setNamespace != null) {
                    if (getNamespace.invoke(androidExt) == null) {
                        setNamespace.invoke(androidExt, "com.irisvision.${name.replace('-', '_')}")
                    }
                }
            } catch (e: Exception) {
                // Ignore if method is unavailable
            }
        }
    }

    if (state.executed) {
        fixNamespace()
    } else {
        afterEvaluate {
            fixNamespace()
        }
    }
}