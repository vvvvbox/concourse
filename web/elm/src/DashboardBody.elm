module DashboardBody exposing
    ( DashboardBody(..)
    , Msg
    , previewBody
    , update
    , view
    )

import Concourse
import Dashboard.Group as Group
import Dashboard.Group.Tag as Tag
import Dashboard.Pipeline as Pipeline
import DragState
import Grouped
import Html exposing (Html)
import Html.Attributes exposing (class)
import Ordering exposing (Ordering)
import PreviewGroup
import PreviewPipeline
import SummaryGroup
import SummaryPipeline
import Tagged
import Time exposing (Time)


type DashboardBody
    = WithTags (List (Tagged.Tagged PreviewGroup.PreviewGroup))
    | WithTagsHd (List (Tagged.Tagged SummaryGroup.SummaryGroup))
    | WithoutTags (List PreviewGroup.PreviewGroup)
    | WithoutTagsHd (List SummaryGroup.SummaryGroup)


type Msg
    = SummaryMsg SummaryPipeline.Msg
    | PreviewMsg PreviewGroup.Msg


isEmpty : DashboardBody -> Bool
isEmpty body =
    case body of
        WithTags groups ->
            List.isEmpty groups

        WithTagsHd groups ->
            List.isEmpty groups

        WithoutTags groups ->
            List.isEmpty groups

        WithoutTagsHd groups ->
            List.isEmpty groups


update : ( Time, ( Group.APIData, Maybe Concourse.User ) ) -> DashboardBody -> DashboardBody
update ( now, ( apiData, user ) ) body =
    let
        allPipelines =
            Group.allPipelines apiData

        allTeamNames =
            Group.allTeamNames apiData

        summaryBody =
            case user of
                Just u ->
                    allTeamNames
                        |> List.map
                            (\teamName ->
                                { teamName = teamName
                                , group =
                                    allPipelines
                                        |> List.filter (.pipeline >> .teamName >> (==) teamName)
                                        |> List.map SummaryPipeline.SummaryPipeline
                                }
                            )
                        |> Tagged.addTagsAndSort u
                        |> WithTagsHd

                Nothing ->
                    allTeamNames
                        |> List.map
                            (\teamName ->
                                { teamName = teamName
                                , group =
                                    allPipelines
                                        |> List.filter (.pipeline >> .teamName >> (==) teamName)
                                        |> List.map SummaryPipeline.SummaryPipeline
                                }
                            )
                        |> WithoutTagsHd
    in
    case body of
        WithTags groups ->
            previewBody now apiData user

        WithTagsHd _ ->
            summaryBody

        WithoutTags groups ->
            previewBody now apiData user

        WithoutTagsHd _ ->
            summaryBody


previewBody : Time -> Group.APIData -> Maybe Concourse.User -> DashboardBody
previewBody now apiData user =
    let
        allPipelines =
            Group.allPipelines apiData

        allTeamNames =
            Group.allTeamNames apiData
    in
    case user of
        Just u ->
            allTeamNames
                |> List.map
                    (\teamName ->
                        { teamName = teamName
                        , group =
                            allPipelines
                                |> List.filter (.pipeline >> .teamName >> (==) teamName)
                                |> List.map (PreviewPipeline.PreviewPipeline now)
                                |> DragState.NotDragging
                        }
                    )
                |> Tagged.addTagsAndSort u
                |> WithTags

        Nothing ->
            allTeamNames
                |> List.map
                    (\teamName ->
                        { teamName = teamName
                        , group =
                            allPipelines
                                |> List.filter (.pipeline >> .teamName >> (==) teamName)
                                |> List.map (PreviewPipeline.PreviewPipeline now)
                                |> DragState.NotDragging
                        }
                    )
                |> WithoutTags


viewGroups : DashboardBody -> List (Html Msg)
viewGroups body =
    case body of
        WithTags groups ->
            groups
                |> List.concatMap (\t -> Tagged.view t ++ [ PreviewGroup.view t.item ])
                |> List.map (Html.map PreviewMsg)

        WithTagsHd groups ->
            groups
                |> List.concatMap (\t -> Tagged.view t ++ [ SummaryGroup.view t.item ])
                |> List.map (Html.map SummaryMsg)

        WithoutTags groups ->
            groups
                |> List.map PreviewGroup.view
                |> List.map (Html.map PreviewMsg)

        WithoutTagsHd groups ->
            groups
                |> List.map SummaryGroup.view
                |> List.map (Html.map SummaryMsg)


view : DashboardBody -> Html Msg
view body =
    if isEmpty body then
        Html.text ""

    else
        Html.div [ class "dashboard-content" ] (viewGroups body)
