// This file relates to internal XMOS infrastructure and should be ignored by external users

@Library('xmos_jenkins_shared_library@v0.38.0') _

def archiveLib(String repoName) {
    sh "git -C ${repoName} clean -xdf"
    sh "zip ${repoName}_sw.zip -r ${repoName}"
    archiveArtifacts artifacts: "${repoName}_sw.zip", allowEmptyArchive: false
}

getApproval()

pipeline {
  agent none
  options {
    buildDiscarder(xmosDiscardBuildSettings())
    skipDefaultCheckout()
    timestamps()
  }
  parameters {
    string(
      name: 'TOOLS_VERSION',
      defaultValue: '15.3.1',
      description: 'The XTC tools version'
    )
    string(
      name: 'XMOSDOC_VERSION',
      defaultValue: 'v7.0.0',
      description: 'The xmosdoc version'
    )
    string(
        name: 'INFR_APPS_VERSION',
        defaultValue: 'v2.1.0',
        description: 'The infr_apps version'
    )
    choice(name: 'TEST_TYPE', choices: ['smoke', 'nightly'],
          description: 'Run tests with either a fixed seed or a randomly generated seed')
  }
  environment {
    REPO = 'lib_xtcp'
    REPO_NAME = 'lib_xtcp'
    SEED = "12345"
  }
  stages {
    stage('Build + Documentation') {
      agent {
        label 'documentation&&linux&&x86_64'
      }
      stages {
        stage('Checkout') {
          // will have a separate python 2 env for running xmostest
          environment {
            PYTHON_VERSION = "3.12.1"
            PIP_VERSION = "24.0"
          }
          steps {
            println "Stage running on: ${env.NODE_NAME}"
            dir("${REPO}") {
              checkoutScmShallow()
              createVenv()
              installPipfile(false)
            }
            dir("${WORKSPACE}") {
              sh "git clone https://github0.xmos.com/xmos-int/tools_xmostest.git"
            }
          }
        }  // Get sandbox

        stage('Examples build') {
          steps{
            dir("${REPO}/examples") {
              withVenv {
                xcoreBuild()
              }
            }
          }
        } // Examples build

        stage('Library checks') {
          steps {
            warnError("lib checks") {
              runLibraryChecks("${WORKSPACE}/${REPO}", "${params.INFR_APPS_VERSION}")
            }
          }
        }
        stage('Documentation') {
          steps {
            dir("${REPO}") {
              warnError("Docs") {
                buildDocs()
              }
            }
          }
        }

        stage('Tests') {
          environment {
            PYTHON_VERSION = "2.7.18"
            PIP_VERSION = "20.3.4"
          }
          steps {
            dir("${REPO}") {
              withTools(params.TOOLS_VERSION) {
                dir("tests") {
                  createVenv(reqFile: "requirements.txt")
                  withVenv{
                    sh "./runtests.py --junit-output=${REPO}_tests.xml"
                  } // withVenv
                } // dir("tests")
              } // withTools
            } // dir("${REPO}")
          } // steps
        } // stage('Tests')

        stage("Archive Lib") {
          steps {
            archiveLib(REPO)
          }
        } //stage("Archive Lib")
      } // stages
      post {
        cleanup {
          xcoreCleanSandbox()
        } // cleanup
        always {
          dir("${WORKSPACE}/${REPO}/tests") {
            // No tests run at this time, uncomment when tests are running.
            // junit "${REPO}_tests.xml"
          }
        }
      } // post
    } // stage('Build + Documentation')
  } // stages
} // pipeline
