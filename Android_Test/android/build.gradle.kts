import groovy.lang.GroovyShell

// Dynamically inject a dummy jcenter() method back to RepositoryHandler to prevent outdated
// third-party plugins (like wifi_iot) from crashing under Gradle 8.0+ / 9.0+.
GroovyShell().evaluate("""
    import org.gradle.api.artifacts.dsl.RepositoryHandler
    RepositoryHandler.metaClass.jcenter = { ->
        delegate.mavenCentral()
    }
""")

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
