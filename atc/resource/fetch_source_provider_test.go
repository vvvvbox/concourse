package resource_test

import (
	"errors"

	"code.cloudfoundry.org/lager"
	"code.cloudfoundry.org/lager/lagertest"
	"github.com/cloudfoundry/bosh-cli/director/template"
	"github.com/concourse/concourse/atc"
	"github.com/concourse/concourse/atc/creds"
	"github.com/concourse/concourse/atc/db/dbfakes"
	"github.com/concourse/concourse/atc/resource"
	"github.com/concourse/concourse/atc/resource/resourcefakes"
	"github.com/concourse/concourse/atc/worker"
	"github.com/concourse/concourse/atc/worker/workerfakes"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

var _ = Describe("FetchSourceProvider", func() {
	var (
		fakeWorkerClient      *workerfakes.FakeClient
		fetchSourceProvider   resource.FetchSourceProvider
		fakeBuildStepDelegate *workerfakes.FakeImageFetchingDelegate

		logger                   lager.Logger
		resourceInstance         *resourcefakes.FakeResourceInstance
		metadata                 = resource.EmptyMetadata{}
		session                  = resource.Session{}
		tags                     atc.Tags
		resourceTypes            creds.VersionedResourceTypes
		teamID                   = 3
		fakeResourceCacheFactory *dbfakes.FakeResourceCacheFactory
		fakeUsedResourceCache    *dbfakes.FakeUsedResourceCache
	)

	BeforeEach(func() {
		fakeWorkerClient = new(workerfakes.FakeClient)
		fakeResourceCacheFactory = new(dbfakes.FakeResourceCacheFactory)
		fakeUsedResourceCache = new(dbfakes.FakeUsedResourceCache)
		fetchSourceProviderFactory := resource.NewFetchSourceProviderFactory(fakeWorkerClient, fakeResourceCacheFactory)
		logger = lagertest.NewTestLogger("test")
		resourceInstance = new(resourcefakes.FakeResourceInstance)
		tags = atc.Tags{"some", "tags"}

		variables := template.StaticVariables{
			"secret-repository": "repository",
		}

		resourceTypes = creds.NewVersionedResourceTypes(variables, atc.VersionedResourceTypes{
			{
				ResourceType: atc.ResourceType{
					Name:   "some-resource",
					Type:   "some-resource",
					Source: atc.Source{"some": "((secret-source))"},
				},
				Version: atc.Version{"some": "version"},
			},
		})

		resourceInstance.ResourceTypeReturns("some-resource-type")
		fakeBuildStepDelegate = new(workerfakes.FakeImageFetchingDelegate)
		fakeUsedResourceCache.IDReturns(42)
		fakeResourceCacheFactory.FindOrCreateResourceCacheReturns(fakeUsedResourceCache, nil)

		fetchSourceProvider = fetchSourceProviderFactory.NewFetchSourceProvider(
			logger,
			session,
			metadata,
			tags,
			teamID,
			resourceTypes,
			resourceInstance,
			fakeBuildStepDelegate,
		)
	})

	Describe("Get", func() {
		It("tries to find satisfying worker", func() {
			_, err := fetchSourceProvider.Get()
			Expect(err).NotTo(HaveOccurred())
			Expect(fakeWorkerClient.SatisfyingCallCount()).To(Equal(1))
			_, resourceSpec, actualResourceTypes := fakeWorkerClient.SatisfyingArgsForCall(0)
			Expect(resourceSpec).To(Equal(worker.WorkerSpec{
				ResourceType: "some-resource-type",
				Tags:         tags,
				TeamID:       teamID,
			}))
			Expect(actualResourceTypes).To(Equal(resourceTypes))
		})

		Context("when worker is found for resource types", func() {
			var fakeWorker *workerfakes.FakeWorker

			BeforeEach(func() {
				fakeWorker = new(workerfakes.FakeWorker)
				fakeWorkerClient.SatisfyingReturns(fakeWorker, nil)
			})

			It("returns resource instance source", func() {
				source, err := fetchSourceProvider.Get()
				Expect(err).NotTo(HaveOccurred())

				expectedSource := resource.NewResourceInstanceFetchSource(
					logger,
					resourceInstance,
					fakeWorker,
					resourceTypes,
					tags,
					teamID,
					session,
					metadata,
					fakeBuildStepDelegate,
					fakeResourceCacheFactory,
				)
				Expect(source).To(Equal(expectedSource))
			})
		})

		Context("when worker is not found for resource types", func() {
			var workerNotFoundErr error

			BeforeEach(func() {
				workerNotFoundErr = errors.New("not-found")
				fakeWorkerClient.SatisfyingReturns(nil, workerNotFoundErr)
			})

			It("returns an error", func() {
				_, err := fetchSourceProvider.Get()
				Expect(err).To(HaveOccurred())
				Expect(err).To(Equal(workerNotFoundErr))
			})
		})
	})
})
