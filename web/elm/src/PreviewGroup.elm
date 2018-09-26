module PreviewGroup exposing
    ( Msg(..)
    , PreviewGroup
    , draggableAttrs
    , pipelineAttrs
    , view
    , viewDragItem
    )

import Concourse.PipelineStatus
import Dashboard.Pipeline as Pipeline
import DragEvent
import DragItem
import DragState
import DragZone
import DropZone
import Grouped
import Html exposing (Html)
import Html.Attributes exposing (attribute, class, classList, draggable, id)
import Html.Events exposing (on)
import Json.Decode
import PreviewPipeline
import Regex exposing (HowMany(All), regex, replace)
import Simple.Fuzzy exposing (filter, match, root)
import ZipList


type alias PreviewGroup =
    Grouped.Grouped (DragState.DragState PreviewPipeline.PreviewPipeline)


type Msg
    = DragMsg (DragEvent.Msg PreviewPipeline.PreviewPipeline)
    | PipelineMsg PreviewPipeline.Msg


view : PreviewGroup -> Html Msg
view ({ group, teamName } as grouped) =
    Html.div [ id teamName, class "dashboard-team-group", attribute "data-team-name" teamName ]
        [ Html.div [ class "pin-wrapper" ]
            [ Html.div [ class "dashboard-team-header" ] [ Grouped.header grouped ] ]
        , Html.div [ class "dashboard-team-pipelines" ]
            (group |> DragItem.items |> List.map viewDragItem)
        ]


viewDragItem : DragItem.DragItem PreviewPipeline.PreviewPipeline -> Html Msg
viewDragItem dragItem =
    case dragItem of
        DragItem.DragZone dragZoneState ->
            case dragZoneState of
                DragZone.Draggable ({ item, rest } as zipList) ->
                    case item of
                        PreviewPipeline.PreviewPipeline now pipeline ->
                            Html.div
                                (pipelineAttrs pipeline ++ draggableAttrs zipList)
                                [ Html.div [ class "dashboard-pipeline-banner" ] []
                                , Html.map PipelineMsg <| PreviewPipeline.view item
                                ]

                DragZone.NonDraggable ((PreviewPipeline.PreviewPipeline now pipeline) as item) ->
                    Html.div
                        (pipelineAttrs pipeline)
                        [ Html.div [ class "dashboard-pipeline-banner" ] []
                        , Html.map PipelineMsg <| PreviewPipeline.view item
                        ]

        DragItem.DropZone dropZoneState ->
            Html.map DragMsg <| DropZone.view dropZoneState


pipelineAttrs : Pipeline.PipelineWithJobs -> List (Html.Attribute msg)
pipelineAttrs pipeline =
    [ classList
        [ ( "dashboard-pipeline", True )
        , ( "dashboard-paused", pipeline.pipeline.paused )
        , ( "dashboard-running", not <| List.isEmpty <| List.filterMap .nextBuild pipeline.jobs )
        , ( "dashboard-status-" ++ Concourse.PipelineStatus.show (Pipeline.pipelineStatusFromJobs pipeline.jobs False), not pipeline.pipeline.paused )
        , ( "dragging", False )
        ]
    , attribute "data-pipeline-name" pipeline.pipeline.name
    ]


draggableAttrs : ZipList.ZipList PreviewPipeline.PreviewPipeline -> List (Html.Attribute Msg)
draggableAttrs zipList =
    [ attribute "ondragstart" "event.dataTransfer.setData('text/plain', '');"
    , draggable "true"
    , on "dragstart" (Json.Decode.succeed (DragMsg <| DragEvent.DragStart zipList))
    , on "dragend" (Json.Decode.succeed (DragMsg DragEvent.Drop))
    ]


filterTerms : String -> List String
filterTerms =
    replace All (regex "team:\\s*") (\_ -> "team:")
        >> replace All (regex "status:\\s*") (\_ -> "status:")
        >> String.words
        >> List.filter (not << String.isEmpty)


filter : String -> List PreviewGroup -> List PreviewGroup
filter =
    filterTerms >> flip (List.foldl filterGroupsByTerm)


pipelines : PreviewGroup -> List PreviewPipeline.PreviewPipeline
pipelines pg =
    case pg.group of
        DragState.NotDragging ps ->
            ps

        DragState.Dragging dl ->
            []


filterPipelinesByTerm : String -> PreviewGroup -> PreviewGroup
filterPipelinesByTerm term pg =
    let
        searchStatus =
            String.startsWith "status:" term

        statusSearchTerm =
            if searchStatus then
                String.dropLeft 7 term

            else
                term

        pgPipelines =
            pipelines pg

        filterByStatus =
            fuzzySearch (\(PreviewPipeline.PreviewPipeline _ p) -> p |> Pipeline.pipelineStatus |> Concourse.PipelineStatus.show) statusSearchTerm pgPipelines

        filteredPipelines =
            if searchStatus then
                filterByStatus

            else
                fuzzySearch (\(PreviewPipeline.PreviewPipeline _ p) -> p.pipeline.name) term pgPipelines
    in
    { pg | group = DragState.NotDragging filteredPipelines }


filterGroupsByTerm : String -> List PreviewGroup -> List PreviewGroup
filterGroupsByTerm term groups =
    let
        searchTeams =
            String.startsWith "team:" term

        teamSearchTerm =
            if searchTeams then
                String.dropLeft 5 term

            else
                term
    in
    if searchTeams then
        fuzzySearch .teamName teamSearchTerm groups

    else
        groups |> List.map (filterPipelinesByTerm term)


fuzzySearch : (a -> String) -> String -> List a -> List a
fuzzySearch map needle records =
    let
        negateSearch =
            String.startsWith "-" needle
    in
    if negateSearch then
        List.filter (not << Simple.Fuzzy.match needle << map) records

    else
        List.filter (Simple.Fuzzy.match needle << map) records
