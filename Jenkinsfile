// macos-app-pipeline-mb — CI for arcana-macos.
// Runs on the Mac mini agent (SwiftUI/SwiftData/AppKit need a real macOS toolchain), builds
// and tests the package, exports coverage, enforces the arch-qube architecture gate, and
// runs a SonarQube analysis gated on the quality gate.
pipeline {
    agent { label 'macmini' }

    options {
        timeout(time: 40, unit: 'MINUTES')
        timestamps()
        disableConcurrentBuilds()
    }

    environment {
        SONAR_SERVER = 'sonar'          // Jenkins "SonarQube servers" configuration name
        SONAR_SCANNER = 'sonar-scanner' // Jenkins "SonarQube Scanner" tool name
    }

    stages {
        stage('Checkout') {
            steps { checkout scm }
        }

        stage('Build') {
            steps {
                sh 'swift --version'
                sh 'swift build'
            }
        }

        stage('Test + Coverage') {
            steps {
                sh 'bash scripts/coverage.sh'
            }
        }

        stage('arch-qube') {
            steps {
                // Prove the gate is not blind, then enforce it (must be 100% green).
                sh 'bash scripts/arch-qube.sh selftest'
                sh 'bash scripts/arch-qube.sh'
            }
        }

        stage('SonarQube analysis') {
            steps {
                script {
                    def scannerHome = tool env.SONAR_SCANNER
                    withSonarQubeEnv(env.SONAR_SERVER) {
                        sh "${scannerHome}/bin/sonar-scanner"
                    }
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 10, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'coverage.lcov', allowEmptyArchive: true, fingerprint: true
        }
    }
}
