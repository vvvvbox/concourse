module PreviewPipeline exposing
    ( Msg(..)
    , PreviewPipeline(..)
    , footerView
    , headerView
    , pauseToggleView
    , togglePipelinePaused
    , transitionView
    , view
    )

import Concourse
import Concourse.Pipeline
import Dashboard.Pipeline as Pipeline
import DashboardPreview
import Html exposing (Html)
import Html.Attributes exposing (class, classList, draggable, href)
import Html.Events exposing (onMouseEnter)
import Routes
import StrictEvents exposing (onLeftClick)
import Task
import Time exposing (Time)


type PreviewPipeline
    = PreviewPipeline Time Pipeline.PipelineWithJobs


type Msg
    = Noop
    | Tooltip String String
    | TogglePipelinePaused Concourse.Pipeline


view : PreviewPipeline -> Html Msg
view (PreviewPipeline now ({ pipeline, jobs, resourceError } as pipelineWithJobs)) =
    Html.div [ class "dashboard-pipeline-content" ]
        [ headerView pipelineWithJobs
        , DashboardPreview.view jobs
        , footerView pipelineWithJobs now
        ]


headerView : Pipeline.PipelineWithJobs -> Html Msg
headerView ({ pipeline, resourceError } as pipelineWithJobs) =
    Html.a [ href <| Routes.pipelineRoute pipeline, draggable "false" ]
        [ Html.div
            [ class "dashboard-pipeline-header"
            , onMouseEnter <| Tooltip pipeline.name pipeline.teamName
            ]
            [ Html.div [ class "dashboard-pipeline-name" ]
                [ Html.text pipeline.name ]
            , Html.div [ classList [ ( "dashboard-resource-error", resourceError ) ] ] []
            ]
        ]


footerView : Pipeline.PipelineWithJobs -> Time -> Html Msg
footerView pipelineWithJobs now =
    Html.div [ class "dashboard-pipeline-footer" ]
        [ Html.div [ class "dashboard-pipeline-icon" ] []
        , transitionView now pipelineWithJobs
        , pauseToggleView pipelineWithJobs.pipeline
        ]


transitionView : Time -> Pipeline.PipelineWithJobs -> Html a
transitionView time pipeline =
    Html.div [ class "build-duration" ]
        [ Html.text <| Pipeline.statusAgeText pipeline time ]


pauseToggleView : Concourse.Pipeline -> Html Msg
pauseToggleView pipeline =
    Html.a
        [ classList
            [ ( "pause-toggle", True )
            , ( "icon-play", pipeline.paused )
            , ( "icon-pause", not pipeline.paused )
            ]
        , onLeftClick <| TogglePipelinePaused pipeline
        ]
        []


togglePipelinePaused : Concourse.Pipeline -> Concourse.CSRFToken -> Cmd Msg
togglePipelinePaused pipeline csrfToken =
    Task.attempt (always Noop) <|
        if pipeline.paused then
            Concourse.Pipeline.unpause pipeline.teamName pipeline.name csrfToken

        else
            Concourse.Pipeline.pause pipeline.teamName pipeline.name csrfToken
