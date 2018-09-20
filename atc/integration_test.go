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
		fmt.Println("====== do login function")
		loginURL := fmt.Sprintf("http://127.0.0.1:%v/sky/login", cmd.BindPort)

		fmt.Println("========== login URL: ", loginURL)

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

		fmt.Println("======= set username/password values")

		resp, err = client.PostForm(location, data)
		fmt.Println("========== sent post data with client")

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
		teamName := "random-team"
		var client http.Client
		var ccClient concourse.Client

		JustBeforeEach(func() {
			client = doLogin("test", "test")
			fmt.Println("============= cmd bind port in just before each for teams:", cmd.BindPort)
			res := fmt.Sprintf("http://127.0.0.1:%v", cmd.BindPort)
			ccClient = concourse.NewClient(res, &client, false)
		})

		Context("when there are defined roles for users", func() {
			Context("when the role is viewer", func() {
				JustBeforeEach(func() {

					team := atc.Team{
						Name: teamName,
						Auth: atc.TeamAuth{
							"viewer": atc.TeamRole{
								"users":  []string{"local:v-user"},
								"groups": []string{},
							},
						},
					}

					_, _, _, err := ccClient.Team(teamName).CreateOrUpdate(team)
					Expect(err).ToNot(HaveOccurred())

					teams, err := ccClient.ListTeams()
					Expect(err).ToNot(HaveOccurred())
					Expect(teams).To(ContainElement(team))

					// resp, err = client.Get(fmt.Sprintf("http://127.0.0.1:%v/api/v1/teams", cmd.BindPort))
					// Expect(err).ToNot(HaveOccurred())
					// Expect(resp.StatusCode).To(Equal(http.StatusOK))

					// bodyBytes, err := ioutil.ReadAll(resp.Body)
					// Expect(string(bodyBytes)).To(ContainSubstring("random/viewer"))
					// Expect(string(bodyBytes)).To(ContainSubstring("local:viewer"))

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
					ccClient.Team(teamName).CreateOrUpdatePipelineConfig("pipeline-name", "0", pipelineData, false)

					doLogin("v-user", "v-user")
				})

				It("should be able to view pipelines", func() {
					resp, err := client.Get(fmt.Sprintf("http://127.0.0.1:%v/api/v1/teams/%s/pipelines", cmd.BindPort, teamName))
					Expect(err).ToNot(HaveOccurred())
					Expect(resp.StatusCode).To(Equal(http.StatusOK))
				})

				It("should NOT be able to set pipelines", func() {
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

					_, _, _, err := ccClient.Team(teamName).CreateOrUpdatePipelineConfig("pipeline-new", "0", pipelineData, false)

					Expect(err).To(HaveOccurred())
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
