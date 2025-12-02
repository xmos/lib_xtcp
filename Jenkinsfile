// This file relates to internal XMOS infrastructure and should be ignored by external users

@Library('xmos_jenkins_shared_library@v0.43.3') _

getApproval()

pipeline {

  agent none

  parameters {
    string(
      name: 'TOOLS_VERSION',
      defaultValue: '15.3.1',
      description: 'The XTC tools version'
    )
    string(
      name: 'XMOSDOC_VERSION',
      defaultValue: 'v8.0.0',
      description: 'The xmosdoc version'
    )
    string(
        name: 'INFR_APPS_VERSION',
        defaultValue: 'v3.2.1',
        description: 'The infr_apps version'
    )
    choice(
      name: 'TEST_TYPE', choices: ['smoke', 'nightly'],
      description: 'Run tests with either a fixed seed or a randomly generated seed'
    )
  }

  options {
    buildDiscarder(xmosDiscardBuildSettings(onlyArtifacts = false))
    skipDefaultCheckout()
    timestamps()
  }

  environment {
    SEED = "12345"
  }
  stages {
    stage('🏗️ Build and Documentation') {
      agent {
        label 'documentation && linux && x86_64'
      }

      stages {
        stage('Checkout') {
          steps {

            println "Stage running on ${env.NODE_NAME}"

            script {
              def (server, user, repo) = extractFromScmUrl()
              env.REPO_NAME = repo
            }

            dir(REPO_NAME) {
              checkoutScmShallow()
            }
          }
        }
        
        stage('Examples build') {
          steps {
            dir("${REPO_NAME}/examples") {
              xcoreBuild()
              stash includes: '**/*.xe', name: 'webserver_test_bin', useDefaultExcludes: false
            }
          }
        }

        stage('Tests build') {
          steps {
            dir("${REPO_NAME}/tests") {
              xcoreBuild()
              stash includes: '**/*.xe', name: 'xtcp_test_bin', useDefaultExcludes: false
              
              withTools(params.TOOLS_VERSION) {
                // Makefile test build, building lib_xtcp is the test
                dir("xtcp_xcommon_build") {
                  sh "xmake -j"
                }
              }
            }
          }
        }

        stage('Repo checks') {
          steps {
            warnError("Repo checks failed") {
              runRepoChecks("${WORKSPACE}/${REPO_NAME}")
            }
          }
        } // Repo checks

        stage('Doc build') {
          steps {
            dir(REPO_NAME) {
              buildDocs()
            }
          }
        }

        stage("Archive Lib") {
          steps {
            archiveSandbox(REPO_NAME)
          }
        }
      } // stages

      post {
        cleanup {
          xcoreCleanSandbox()
        }
      }
    } // stage('Build + Documentation')


    stage('Tests') {
      parallel {

        stage('Tests: unit tests - lib_unity') {
          agent {
            label 'documentation && linux && x86_64'
          }
          
          steps {
            dir(REPO_NAME) {
              checkoutScmShallow()

              withTools(params.TOOLS_VERSION) {
                dir("tests") {

                  createVenv(reqFile: "requirements.txt")
                  withVenv {
                    dir("unit") {

                      warnError("Pytest failed or test asserted") {
                        sh(script: "python -m pytest -v --junitxml=pytest_unit.xml")
                      }
                    }
                  }
                }
              }
            } // dir(REPO_NAME)
          } // steps

          post {
            always {
              junit "${REPO_NAME}/tests/unit/pytest_unit.xml"
            }
            cleanup {
              xcoreCleanSandbox()
            }
          }
        } // stage('Tests: unit tests - lib_unity')

        stage('Tests: HW tests - PHY0') {
          agent {
            label 'sw-hw-eth-ubu0'
          }

          steps {
            dir(REPO_NAME) {
              checkoutScmShallow()

              dir("examples") {
                unstash 'webserver_test_bin'
              }

              withTools(params.TOOLS_VERSION) {
                dir("tests") {
                  unstash 'xtcp_test_bin'

                  createVenv(reqFile: "requirements.txt")
                  withVenv {
                    warnError("Pytest failed or test asserted") {

                      withXTAG(["xk-eth-xu316-dual-100m"]) {
                        // TODO - link in TEST_TYPE to pytest
                        xtagIds ->
                          sh(script: "python -m pytest -v --junitxml=pytest_checks.xml --adapter-id ${xtagIds[0]} -k 'XMS0020' --ignore=unit")
                      }
                    }
                  }
                }
              }
            } // dir(REPO_NAME)
          } // steps

          post {
            always {
              junit "${REPO_NAME}/tests/pytest_checks.xml"
            }
            cleanup {
              xcoreCleanSandbox()
            }
          }
        } // stage('Tests: HW tests - PHY0')

        stage('Tests: HW tests - regression') {
          agent {
            label 'sw-hw-eth-ubu2'
          }

          steps {
            dir(REPO_NAME) {
              checkoutScmShallow()

              dir("examples") {
                unstash 'webserver_test_bin'
              }

              withTools(params.TOOLS_VERSION) {
                dir("tests") {
                  unstash 'xtcp_test_bin'

                  createVenv(reqFile: "requirements.txt")
                  withVenv {
                    warnError("Pytest failed or test asserted") {

                      withXTAG(["xk-eth-316-dual"]) {
                        // TODO - link in TEST_TYPE to pytest
                        xtagIds ->
                          sh(script: "python -m pytest -v --junitxml=pytest_xk_eth_316_dual.xml --adapter-id ${xtagIds[0]} -k 'webserver or XK_ETH_316_DUAL' --ignore=unit")
                      }
                      withXTAG(["xk-evk-xe216"]) {
                        // TODO - link in TEST_TYPE to pytest
                        xtagIds ->
                          sh(script: "python -m pytest -v --junitxml=pytest_xk-evk-xe216.xml --adapter-id ${xtagIds[0]} -k 'XK_EVK_XE216' --ignore=unit")
                      }
                    }
                  }
                }
              }
            } // dir(REPO_NAME)
          } // steps

          post {
            always {
              junit "${REPO_NAME}/tests/pytest_xk_eth_316_dual.xml"
              junit "${REPO_NAME}/tests/pytest_xk-evk-xe216.xml"
            }
            cleanup {
              xcoreCleanSandbox()
            }
          }
        } // stage('Tests: HW tests - PHY0')


      } // parallel
    } // stage('Tests')
    
    stage('🚀 Release') {
      when {
        expression { triggerRelease.isReleasable() }
      }
      steps {
        triggerRelease()
      }
    }
  } // stages
} // pipeline
