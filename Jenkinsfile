// macos-app-pipeline-mb — CI for arcana-macos.
//
// The Swift build/test/arch-qube stages run on the Mac mini agent (SwiftUI/SwiftData/AppKit
// need a real macOS toolchain); the SonarQube analysis runs on the built-in node, which has
// Docker + the devops_default network to reach SonarQube (mirroring the arcana-ios pipeline).
pipeline {
    agent none

    environment {
        SQ_URL   = 'http://sonarqube:9000/sonarqube'
        SQ_TOKEN = 'squ_5ce2319b9d8ca2b1db4e0f5bdf36b34249561f18'
    }

    options {
        timeout(time: 40, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    stages {
        stage('Build · Test · arch-qube') {
            agent { label 'macmini' }
            steps {
                checkout scm
                sh 'swift --version'
                sh 'swift build'
                // Tests + coverage, converted to the SonarQube generic coverage format.
                sh 'bash scripts/coverage.sh'
                sh 'python3 scripts/lcov_to_sonar.py coverage.lcov coverage-report.xml || echo "coverage convert failed (non-fatal)"'
                // Architecture gate — prove it is not blind, then enforce it (must be 100%).
                sh 'bash scripts/arch-qube.sh selftest'
                sh 'bash scripts/arch-qube.sh'
                stash includes: 'Sources/**,coverage-report.xml,sonar-project.properties',
                      name: 'sonar-inputs', allowEmpty: true
                archiveArtifacts artifacts: 'coverage.lcov,coverage-report.xml',
                      allowEmptyArchive: true, fingerprint: true
            }
        }

        stage('SonarQube analysis + Quality Gate') {
            agent { label 'built-in' }
            steps {
                unstash 'sonar-inputs'
                // Official scanner image on the devops_default network. `qualitygate.wait`
                // makes the scanner block on the gate and fail the build if it is red — no
                // Jenkins webhook needed.
                //
                // Docker-outside-of-Docker: the Jenkins container's /var/jenkins_home is bind-
                // mounted from the host at /opt/arcana-state/jenkins-home, so the daemon needs
                // the HOST path for the volume mount, not the in-container ${WORKSPACE}.
                sh '''
                    HOST_WS=$(printf '%s' "${WORKSPACE}" | sed 's#^/var/jenkins_home#/opt/arcana-state/jenkins-home#')
                    docker run --rm \
                        --network devops_default \
                        -e SONAR_HOST_URL=${SQ_URL} \
                        -e SONAR_TOKEN=${SQ_TOKEN} \
                        -v "${HOST_WS}:/usr/src" \
                        sonarsource/sonar-scanner-cli:11 \
                        -Dsonar.projectKey=arcana-macos \
                        "-Dsonar.projectName=Arcana macOS" \
                        -Dsonar.sources=Sources \
                        "-Dsonar.exclusions=**/.build/**,Sources/ArcanaMacApp/**" \
                        "-Dsonar.coverage.exclusions=Tests/**,Sources/ArcanaMacApp/**,**/*App.swift,**/*View.swift,**/CompositionRoot.swift" \
                        -Dsonar.coverageReportPaths=coverage-report.xml \
                        -Dsonar.scm.disabled=true \
                        -Dsonar.qualitygate.wait=true
                '''
            }
        }
    }

    post {
        success { echo 'arcana-macos CI OK (build + tests + arch-qube + SonarQube gate green)' }
        failure { echo 'arcana-macos CI FAILED' }
    }
}
