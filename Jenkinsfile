// This file relates to internal XMOS infrastructure and should be ignored by external users

@Library('xmos_jenkins_shared_library@v0.38.0') _

def clone_test_deps() {
  dir("${WORKSPACE}") {
    sh "git clone git@github.com:xmos/test_support"
    sh "git -C test_support checkout e62b73a1260069c188a7d8fb0d91e1ef80a3c4e1"

    sh "git clone git@github.com:xmos/hardware_test_tools"
    sh "git -C hardware_test_tools checkout 2f9919c956f0083cdcecb765b47129d846948ed4"

    sh "git clone git@github0.xmos.com:xmos-int/xtagctl"
    sh "git -C xtagctl checkout v3.0.0"
  }
}

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
      defaultValue: 'v6.3.1',
      description: 'The xmosdoc version'
    )
    string(
        name: 'INFR_APPS_VERSION',
        defaultValue: 'v2.0.1',
        description: 'The infr_apps version'
    )
    choice(name: 'TEST_TYPE', choices: ['smoke', 'nightly'],
          description: 'Run tests with either a fixed seed or a randomly generated seed')
  }
  environment {
    REPO = 'lib_xtcp'
    REPO_NAME = 'lib_xtcp'
    PIP_VERSION = "24.0"
    SEED = "12345"
  }
  stages {
    stage('Build + Documentation') {
      agent {
        label 'documentation&&linux&&x86_64'
      }
      stages {
        stage('Checkout') {
          environment {
            PYTHON_VERSION = "3.12.1"
          }
          steps {
            println "Stage running on: ${env.NODE_NAME}"
            dir("${REPO}") {
              checkoutScmShallow()
              createVenv()
              installPipfile(false)
            }
          }
        }  // Get sandbox

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
        stage('Build tests') {
          steps {
            dir("${REPO}") {
              withVenv {
                withTools(params.TOOLS_VERSION) {
                  dir("tests") {
                    xcoreBuild()
                    stash includes: '**/*.xe', name: 'test_bin', useDefaultExcludes: false
                  }
                } // withTools(params.TOOLS_VERSION)
              } // withVenv
            } // dir("${REPO}")
          } // steps
        } // stage('Build tests')
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
      } // post
    } // stage('Build + Documentation')
  } // stages
} // pipeline
