package atc_test

import (
	"crypto/rand"
	"crypto/rsa"
	"fmt"
	"io/ioutil"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"os"
	"time"

	"github.com/concourse/concourse/atc"
	"github.com/concourse/concourse/atc/atccmd"
	"github.com/concourse/concourse/atc/postgresrunner"
	concourse "github.com/concourse/concourse/go-concourse/concourse"
	helpers "github.com/concourse/concourse/testflight/helpers"
	"github.com/concourse/flag"
	flags "github.com/jessevdk/go-flags"
	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"github.com/tedsuo/ifrit"
	"github.com/tedsuo/ifrit/ginkgomon"
)

var _ = Describe("ATC Integration Test", func() {
	var (
		postgresRunner postgresrunner.Runner
		dbProcess      ifrit.Process
		atcProcess     ifrit.Process
		cmd            *atccmd.RunCommand
	)

	BeforeEach(func() {
		postgresRunner = postgresrunner.Runner{
			Port: 5433 + GinkgoParallelNode(),
		}
		dbProcess = ifrit.Invoke(postgresRunner)
		postgresRunner.CreateTestDB()

		// workaround to avoid panic due to registering http handlers multiple times
		http.DefaultServeMux = new(http.ServeMux)
		cmd = RunCommand()
	})

	JustBeforeEach(func() {
		cmd.BindPort = 9090 + uint16(GinkgoParallelNode())
		cmd.DebugBindPort = 0

		runner, _, err := cmd.Runner([]string{})
		Expect(err).NotTo(HaveOccurred())

		atcProcess = ginkgomon.Invoke(runner)

		Eventually(func() error {
			_, err := http.Get(fmt.Sprintf("http://localhost:%v/api/v1/info", cmd.BindPort))
			return err
		}, 20*time.Second).ShouldNot(HaveOccurred())
	})

	AfterEach(func() {
		atcProcess.Signal(os.Kill)
		<-atcProcess.Wait()
		dbProcess.Signal(os.Kill)
		<-dbProcess.Wait()
	})

	doLogin := func(username, password string) http.Client {
		loginURL := fmt.Sprintf("http://127.0.0.1:%v/sky/login", cmd.BindPort)

		jar, err := cookiejar.New(nil)
		Expect(err).NotTo(HaveOccurred())
		client := http.Client{
			Jar: jar,
		}
		resp, err := client.Get(loginURL)
		Expect(err).NotTo(HaveOccurred())
		Expect(resp.StatusCode).To(Equal(200))
		location := resp.Request.URL.String()

		data := url.Values{
			"login":    []string{username},
			"password": []string{password},
		}

		resp, err = client.PostForm(location, data)
		Expect(err).NotTo(HaveOccurred())

		bodyBytes, err := ioutil.ReadAll(resp.Body)
		Expect(resp.StatusCode).To(Equal(200))
		Expect(string(bodyBytes)).ToNot(ContainSubstring("invalid username and password"))

		return client
	}

	Context("when no signing key is provided", func() {
		It("logs in successfully", func() {
			doLogin("test", "test")
		})
	})

	Context("when the bind ip is 0.0.0.0 and a signing key is provided", func() {
		BeforeEach(func() {
			key, err := rsa.GenerateKey(rand.Reader, 2048)
			Expect(err).NotTo(HaveOccurred())
			cmd.Auth.AuthFlags.SigningKey = &flag.PrivateKey{PrivateKey: key}
		})

		It("successfully redirects logins to localhost", func() {
			doLogin("test", "test")
		})
	})

	FContext("Teams", func() {
		teamName := "random"
		var client http.Client
		var goConcourseClient concourse.Client
		var atcURL string
		var team atc.Team

		pipelineData := []byte(`
---
jobs:
- name: simple
	plan:
	- task: simple-task
		config:
			platform: linux
			image_resource:
				type: registry-image
				source: {repository: busybox}
			run:
				path: echo
				args: ["Hello, world!"]
					`)

		JustBeforeEach(func() {
			client = doLogin("test", "test")
			atcURL = fmt.Sprintf("http://127.0.0.1:%v", cmd.BindPort)
			goConcourseClient = helpers.ConcourseClient(atcURL, "test", "test")
		})

		FContext("when there are defined roles for users", func() {
			Context("when the role is viewer", func() {
				JustBeforeEach(func() {
					team = atc.Team{
						Name: teamName,
						Auth: atc.TeamAuth{
							"viewer": atc.TeamRole{
								"users":  []string{"local:v-user"},
								"groups": []string{},
							},
							"owner": atc.TeamRole{
								"users":  []string{"local:test"},
								"groups": []string{},
							},
						},
					}

					createdTeam, _, _, err := goConcourseClient.Team(teamName).CreateOrUpdate(team)
					Expect(err).ToNot(HaveOccurred())
					Expect(createdTeam.Name).To(Equal(team.Name))
					Expect(createdTeam.Auth).To(Equal(team.Auth))

					// why does this pipelineConfig throw a malformed error?
					pipelineData := []byte(`
---
jobs:
- name: simple
`)

					// Have to login again to get token with new team user roles in order to
					// have the permissions to set a pipeline
					goConcourseClient = helpers.ConcourseClient(atcURL, "test", "test")
					_, _, _, err = goConcourseClient.Team(teamName).CreateOrUpdatePipelineConfig("pipeline-name", "0", pipelineData, false)
					Expect(err).ToNot(HaveOccurred())
				})

				It("should be able to view pipelines", func() {
					// go concourse-client reinitialization with v-user to generate new token
					goConcourseClient = helpers.ConcourseClient(atcURL, "v-user", "v-user")

					pipelines, err := goConcourseClient.Team(teamName).ListPipelines()
					Expect(err).ToNot(HaveOccurred())
					Expect(pipelines).ToNot(BeNil())
				})

				It("should NOT be able to set pipelines", func() {
					_, _, _, err := goConcourseClient.Team(teamName).CreateOrUpdatePipelineConfig("pipeline-new", "0", pipelineData, false)
					Expect(err).To(HaveOccurred())
				})
			})

			Context("when the role is member", func() {
				JustBeforeEach(func() {
					team = atc.Team{
						Name: teamName,
						Auth: atc.TeamAuth{
							"member": atc.TeamRole{
								"users":  []string{"local:v-member"},
								"groups": []string{},
							},
							"owner": atc.TeamRole{
								"users":  []string{"local:test"},
								"groups": []string{},
							},
						},
					}
				})

				It("should be able to view the pipelines", func() {
				})

				It("should NOT be able to set pipelines", func() {
				})
			})

			Context("when the role is owner", func() {
				JustBeforeEach(func() {
					team = atc.Team{
						Name: teamName,
						Auth: atc.TeamAuth{
							"owner": atc.TeamRole{
								"users":  []string{"local:test"},
								"groups": []string{},
							},
						},
					}
				})

				// these 2 are kind of tested in the initial BeforeEach...
				It("should be able to view pipelines", func() {
				})

				It("should be able to set pipelines", func() {
				})
			})
		})

		It("set default team and config auth for the main team", func() {
			resp, err := client.Get(fmt.Sprintf("http://127.0.0.1:%v/api/v1/teams", cmd.BindPort))
			Expect(err).NotTo(HaveOccurred())

			bodyBytes, err := ioutil.ReadAll(resp.Body)
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(200))
			Expect(string(bodyBytes)).To(ContainSubstring("main"))
			Expect(string(bodyBytes)).To(ContainSubstring("local:test"))
		})
	})
})

func RunCommand() *atccmd.RunCommand {
	cmd := atccmd.RunCommand{}
	_, err := flags.ParseArgs(&cmd, []string{})
	Expect(err).NotTo(HaveOccurred())
	cmd.Postgres.User = "postgres"
	cmd.Postgres.Database = "testdb"
	cmd.Postgres.Port = 5433 + uint16(GinkgoParallelNode())
	cmd.Postgres.SSLMode = "disable"
	cmd.Auth.MainTeamFlags.LocalUsers = []string{"test"}
	cmd.Auth.AuthFlags.LocalUsers = map[string]string{
		"test":   "test",
		"v-user": "v-user",
		"m-user": "m-user",
		"o-user": "o-user",
	}
	cmd.Logger.LogLevel = "debug"
	cmd.Logger.SetWriterSink(GinkgoWriter)
	return &cmd
}
