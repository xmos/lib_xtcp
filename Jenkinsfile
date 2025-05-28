// This file relates to internal XMOS infrastructure and should be ignored by external users

@Library('xmos_jenkins_shared_library@v0.39.0') _

def clone_test_deps() 
{
  dir("${WORKSPACE}")
  {
    // Check whether we need test_support....
    sh "git clone git@github.com:xmos/test_support"
    sh "git -C test_support checkout e62b73a1260069c188a7d8fb0d91e1ef80a3c4e1"

    sh "git clone git@github.com:xmos/hardware_test_tools"
    sh "git -C hardware_test_tools checkout 2f9919c956f0083cdcecb765b47129d846948ed4"

    sh "git clone git@github0.xmos.com:xmos-int/xtagctl"
    sh "git -C xtagctl checkout v3.0.0"
  }
}

getApproval()

pipeline 
{
  agent none
  options 
  {
    buildDiscarder(xmosDiscardBuildSettings())
    skipDefaultCheckout()
    timestamps()
  }
  parameters 
  {
    string(
      name: 'TOOLS_VERSION',
      defaultValue: '15.3.1',
      description: 'The XTC tools version'
    )
    string(
      name: 'XMOSDOC_VERSION',
      defaultValue: 'v7.3.0',
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
  environment 
  {
    REPO = 'lib_xtcp'
    REPO_NAME = 'lib_xtcp'
    SEED = "12345"
  }
  stages 
  {
    stage('Build + Documentation') 
    {
      agent 
      {
        label 'documentation&&linux&&x86_64'
      }
      stages
      {
        stage('Checkout + Build') 
        {
          steps 
          {
            println "Stage running on: ${env.NODE_NAME}"
            dir("${REPO}") 
            {
              checkoutScmShallow()
              
              dir("examples") 
              {
                withTools(params.TOOLS_VERSION) 
                {
                  xcoreBuild()
                  stash includes: '**/*.xe', name: 'webserver_test_bin', useDefaultExcludes: false
                }
              }

              dir("tests")
              {
                withTools(params.TOOLS_VERSION) 
                {
                  xcoreBuild()
                  stash includes: '**/*.xe', name: 'xtcp_test_bin', useDefaultExcludes: false

                  // xcommon
                  dir("xtcp_xcommon_build")
                  {
                    sh "xmake -j"
                  }
                }
              }
            }
          }
        }  // Get sandbox

        stage('Library checks') 
        {
          steps
          {
            warnError("lib checks") 
            {
              runLibraryChecks("${WORKSPACE}/${REPO}", "${params.INFR_APPS_VERSION}")
            }
          }
        } // Library checks

        stage('Documentation')
        {
          steps 
          {
            dir("${REPO}")
            {
              warnError("Docs")
              {
                buildDocs()
              }
            }
          }
        } // Documentation

        stage("Archive Lib") 
        {
          steps 
          {
            archiveSandbox(REPO)
          }
        }
      } // stages
      post 
      {
        cleanup 
        {
          xcoreCleanSandbox()
        }
      }
    } // stage('Build + Documentation')

    stage('Tests: HW tests - PHY0') 
    {
      agent 
      {
        label 'sw-hw-eth-ubu0'
      }

      steps 
      {
        clone_test_deps()

        dir("${REPO}") 
        {
          checkoutScmShallow()

          dir("examples")
          {
            unstash 'webserver_test_bin'
          }

          withTools(params.TOOLS_VERSION)
          {
            dir("tests")
            {
              unstash 'xtcp_test_bin'

              createVenv(reqFile: "requirements.txt")
              withVenv
              {
                warnError("Pytest failed or test asserted")
                {
                  withXTAG(["xk-eth-xu316-dual-100m"])
                  { 
                    xtagIds ->
                      sh(script: "python -m pytest -v --junitxml=pytest_checks.xml --adapter-id ${xtagIds[0]}")
                  }
                }
                junit 'pytest_checks.xml'
              }
            }
          }
        } // dir("${REPO}")
      } // steps
      
      post
      {
        cleanup 
        {
          xcoreCleanSandbox()
        }
      }
    }
  } // stages
} // pipeline
