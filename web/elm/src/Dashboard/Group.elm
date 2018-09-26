module Dashboard.Group exposing
    ( APIData
    , DragState(..)
    , DropState(..)
    , Msg(..)
    , PipelineIndex
    , allPipelines
    , allTeamNames
    , dragIndex
    , dragIndexOptional
    , dropIndex
    , dropIndexOptional
    , group
    , pipelineNotSetView
    , remoteData
    , setDragIndex
    , setDropIndex
    , setTeamName
    , shiftPipelineTo
    , teamName
    , teamNameOptional
    )

import Concourse
import Concourse.Info
import Concourse.Job
import Concourse.Pipeline
import Concourse.PipelineStatus
import Concourse.Resource
import Concourse.Team
import Dashboard.Pipeline as Pipeline
import Grouped exposing (Grouped)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (on, onMouseEnter)
import Http
import Json.Decode
import List.Extra
import Maybe.Extra
import Monocle.Iso
import Monocle.Lens
import Monocle.Optional
import Ordering exposing (Ordering)
import Set
import Task
import Time exposing (Time)
import ZipList


type alias APIData =
    { teams : List Concourse.Team
    , pipelines : List Concourse.Pipeline
    , jobs : List Concourse.Job
    , resources : List Concourse.Resource
    , version : String
    }


findElementOptional : (a -> Bool) -> Monocle.Optional.Optional (List a) a
findElementOptional predicate =
    Monocle.Optional.Optional (List.Extra.find predicate)
        (\g gs ->
            List.Extra.findIndex predicate gs
                |> Maybe.map (\i -> List.Extra.setAt i g gs)
                |> Maybe.Extra.join
                |> Maybe.withDefault gs
        )


type alias PipelineIndex =
    Int


type DragState
    = NotDragging
    | Dragging Concourse.TeamName PipelineIndex


teamNameOptional : Monocle.Optional.Optional DragState Concourse.TeamName
teamNameOptional =
    Monocle.Optional.Optional teamName setTeamName


dragIndexOptional : Monocle.Optional.Optional DragState PipelineIndex
dragIndexOptional =
    Monocle.Optional.Optional dragIndex setDragIndex


dropIndexOptional : Monocle.Optional.Optional DropState PipelineIndex
dropIndexOptional =
    Monocle.Optional.Optional dropIndex setDropIndex


teamName : DragState -> Maybe Concourse.TeamName
teamName dragState =
    case dragState of
        Dragging teamName _ ->
            Just teamName

        NotDragging ->
            Nothing


setTeamName : Concourse.TeamName -> DragState -> DragState
setTeamName teamName dragState =
    case dragState of
        Dragging _ dragIndex ->
            Dragging teamName dragIndex

        NotDragging ->
            NotDragging


dragIndex : DragState -> Maybe PipelineIndex
dragIndex dragState =
    case dragState of
        Dragging _ dragIndex ->
            Just dragIndex

        NotDragging ->
            Nothing


setDragIndex : PipelineIndex -> DragState -> DragState
setDragIndex dragIndex dragState =
    case dragState of
        Dragging teamName _ ->
            Dragging teamName dragIndex

        NotDragging ->
            NotDragging


type DropState
    = NotDropping
    | Dropping PipelineIndex


dropIndex : DropState -> Maybe PipelineIndex
dropIndex dropState =
    case dropState of
        Dropping dropIndex ->
            Just dropIndex

        NotDropping ->
            Nothing


setDropIndex : PipelineIndex -> DropState -> DropState
setDropIndex dropIndex dropState =
    case dropState of
        Dropping _ ->
            Dropping dropIndex

        NotDropping ->
            NotDropping


type Msg
    = DragStart (ZipList.ZipList Pipeline.PipelineWithJobs)
    | DragOver Pipeline.PipelineWithJobs
    | DragToEnd
    | DragEnd
    | PipelineMsg Pipeline.Msg


allPipelines : APIData -> List Pipeline.PipelineWithJobs
allPipelines data =
    data.pipelines
        |> List.map
            (\p ->
                { pipeline = p
                , jobs =
                    data.jobs
                        |> List.filter
                            (\j ->
                                (j.teamName == p.teamName)
                                    && (j.pipelineName == p.name)
                            )
                , resourceError =
                    data.resources
                        |> List.any
                            (\r ->
                                (r.teamName == p.teamName)
                                    && (r.pipelineName == p.name)
                                    && r.failingToCheck
                            )
                }
            )


shiftPipelineTo : Pipeline.PipelineWithJobs -> Int -> List Pipeline.PipelineWithJobs -> List Pipeline.PipelineWithJobs
shiftPipelineTo ({ pipeline } as pipelineWithJobs) position pipelines =
    case pipelines of
        [] ->
            if position < 0 then
                []

            else
                [ pipelineWithJobs ]

        p :: ps ->
            if p.pipeline.teamName /= pipeline.teamName then
                p :: shiftPipelineTo pipelineWithJobs position ps

            else if p.pipeline == pipeline then
                shiftPipelineTo pipelineWithJobs (position - 1) ps

            else if position == 0 then
                pipelineWithJobs :: p :: shiftPipelineTo pipelineWithJobs (position - 1) ps

            else
                p :: shiftPipelineTo pipelineWithJobs (position - 1) ps


allTeamNames : APIData -> List String
allTeamNames apiData =
    Set.union
        (Set.fromList (List.map .teamName apiData.pipelines))
        (Set.fromList (List.map .name apiData.teams))
        |> Set.toList


remoteData : Task.Task Http.Error APIData
remoteData =
    Task.map5 APIData
        Concourse.Team.fetchTeams
        Concourse.Pipeline.fetchPipelines
        (Concourse.Job.fetchAllJobs |> Task.map (Maybe.withDefault []))
        (Concourse.Resource.fetchAllResources |> Task.map (Maybe.withDefault []))
        (Concourse.Info.fetch |> Task.map .version)



-- TODO i'd like for this to be an isomorphism, which would
-- require adding resource data to the Group type, or making
-- the APIData type smaller (or, like, not marrying Group to
-- APIData at all but using a different type)


group : List Pipeline.PipelineWithJobs -> String -> Grouped (List Pipeline.PipelineWithJobs)
group allPipelines teamName =
    { group = List.filter ((==) teamName << .teamName << .pipeline) allPipelines
    , teamName = teamName
    }


pipelineNotSetView : Html msg
pipelineNotSetView =
    Html.div
        [ class "dashboard-pipeline" ]
        [ Html.div
            [ classList
                [ ( "dashboard-pipeline-content", True )
                , ( "no-set", True )
                ]
            ]
            [ Html.a [] [ Html.text "no pipelines set" ]
            ]
        ]
