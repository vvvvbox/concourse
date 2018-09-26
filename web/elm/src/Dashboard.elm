port module Dashboard exposing (Model, Msg, init, subscriptions, update, view)

import Char
import Concourse
import Concourse.Cli
import Concourse.Pipeline
import Concourse.User
import Dashboard.Details as Details
import Dashboard.Group as Group
import Dashboard.Pipeline as Pipeline
import Dashboard.SubState as SubState
import DashboardBody
import Dom
import Html exposing (Html)
import Html.Attributes exposing (attribute, class, classList, draggable, href, id, src)
import Html.Attributes.Aria exposing (ariaLabel)
import Http
import Keyboard
import Maybe.Extra
import Monocle.Common exposing ((<|>), (=>))
import Monocle.Lens
import Monocle.Optional
import Mouse
import NewTopBar
import NoPipeline exposing (Msg, view)
import RemoteData
import Routes
import Task
import Time exposing (Time)


type alias Ports =
    { title : String -> Cmd Msg
    }


port pinTeamNames : () -> Cmd msg


port tooltip : ( String, String ) -> Cmd msg



-- TODO all the crsfToken stuff in this file only gets actually used for ordering and toggling pipelines.
-- honestly it seems like it could live in a completely different module.


type alias Flags =
    { csrfToken : String
    , turbulencePath : String
    , search : String
    , highDensity : Bool
    }


type DashboardError
    = NotAsked
    | Turbulence String
    | NoPipelines


type alias Model =
    { csrfToken : String
    , state : Result DashboardError SubState.SubState
    , topBar : NewTopBar.Model
    , turbulencePath : String -- this doesn't vary, it's more a prop (in the sense of react) than state. should be a way to use a thunk for the Turbulence case of DashboardState
    , highDensity : Bool
    }


stateLens : Monocle.Lens.Lens Model (Result DashboardError SubState.SubState)
stateLens =
    Monocle.Lens.Lens .state (\b a -> { a | state = b })


substateOptional : Monocle.Optional.Optional Model SubState.SubState
substateOptional =
    Monocle.Optional.Optional (.state >> Result.toMaybe) (\s m -> { m | state = Ok s })


type Msg
    = Noop
    | APIDataFetched (RemoteData.WebData ( Time.Time, ( Group.APIData, Maybe Concourse.User ) ))
    | ClockTick Time.Time
    | AutoRefresh Time
    | ShowFooter
    | KeyPressed Keyboard.KeyCode
    | KeyDowns Keyboard.KeyCode
    | TopBarMsg NewTopBar.Msg
    | BodyMsg DashboardBody.Msg


init : Ports -> Flags -> ( Model, Cmd Msg )
init ports flags =
    let
        ( topBar, topBarMsg ) =
            NewTopBar.init (not flags.highDensity) flags.search
    in
    ( { state = Err NotAsked
      , topBar = topBar
      , csrfToken = flags.csrfToken
      , turbulencePath = flags.turbulencePath
      , highDensity = flags.highDensity
      }
    , Cmd.batch
        [ fetchData
        , Cmd.map TopBarMsg topBarMsg
        , pinTeamNames ()
        , ports.title <| "Dashboard" ++ " - "
        ]
    )


handle : a -> a -> Result e v -> a
handle onError onSuccess result =
    case result of
        Ok _ ->
            onSuccess

        Err _ ->
            onError


substateLens : Monocle.Lens.Lens Model (Maybe SubState.SubState)
substateLens =
    Monocle.Lens.Lens (.state >> Result.toMaybe)
        (\mss model -> Maybe.map (\ss -> { model | state = Ok ss }) mss |> Maybe.withDefault model)


noop : Model -> ( Model, Cmd msg )
noop model =
    ( model, Cmd.none )


substate : String -> Bool -> ( Time.Time, ( Group.APIData, Maybe Concourse.User ) ) -> Result DashboardError SubState.SubState
substate csrfToken highDensity ( now, ( apiData, user ) ) =
    apiData.pipelines
        |> List.head
        |> Maybe.map
            (always
                { body = DashboardBody.previewBody now apiData user
                , details =
                    if highDensity then
                        Nothing

                    else
                        Just
                            { now = now
                            , dragState = Group.NotDragging
                            , dropState = Group.NotDropping
                            , showHelp = False
                            }
                , hideFooter = False
                , hideFooterCounter = 0
                , csrfToken = csrfToken
                , version = apiData.version
                }
            )
        |> Result.fromMaybe NoPipelines


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        reload =
            Cmd.batch <|
                handle [] [ fetchData ] model.state
                    ++ [ Cmd.map TopBarMsg NewTopBar.fetchUser ]
    in
    case msg of
        Noop ->
            ( model, Cmd.none )

        APIDataFetched remoteData ->
            (case remoteData of
                RemoteData.NotAsked ->
                    model |> stateLens.set (Err NotAsked)

                RemoteData.Loading ->
                    model |> stateLens.set (Err NotAsked)

                RemoteData.Failure _ ->
                    model |> stateLens.set (Err (Turbulence model.turbulencePath))

                RemoteData.Success ( now, ( apiData, user ) ) ->
                    model
                        |> Monocle.Lens.modify stateLens
                            (Result.map (Monocle.Lens.modify SubState.bodyLens (DashboardBody.update ( now, ( apiData, user ) )) >> Ok)
                                >> Result.withDefault (substate model.csrfToken model.highDensity ( now, ( apiData, user ) ))
                            )
            )
                |> noop

        ClockTick now ->
            model
                |> Monocle.Optional.modify substateOptional (SubState.tick now)
                |> noop

        AutoRefresh _ ->
            ( model
            , reload
            )

        KeyPressed keycode ->
            handleKeyPressed (Char.fromCode keycode) model

        KeyDowns keycode ->
            update (TopBarMsg (NewTopBar.KeyDown keycode)) model

        ShowFooter ->
            model
                |> Monocle.Optional.modify substateOptional SubState.showFooter
                |> noop

        -- TODO pull the topbar logic right in here. right now there are wasted API calls and this crufty
        -- nonsense going on. however, this feels like a big change and not a big burning fire
        TopBarMsg msg ->
            let
                ( newTopBar, newTopBarMsg ) =
                    NewTopBar.update msg model.topBar

                newMsg =
                    case msg of
                        NewTopBar.LoggedOut (Ok _) ->
                            reload

                        _ ->
                            Cmd.map TopBarMsg newTopBarMsg
            in
            ( { model | topBar = newTopBar }, newMsg )

        BodyMsg msg ->
            ( model, Cmd.none )


orderPipelines : String -> List Pipeline.PipelineWithJobs -> Concourse.CSRFToken -> Cmd Msg
orderPipelines teamName pipelines csrfToken =
    Task.attempt (always Noop) <|
        Concourse.Pipeline.order
            teamName
            (List.map (.name << .pipeline) <| pipelines)
            csrfToken


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Time.every Time.second ClockTick
        , Time.every (5 * Time.second) AutoRefresh
        , Mouse.moves (\_ -> ShowFooter)
        , Mouse.clicks (\_ -> ShowFooter)
        , Keyboard.presses KeyPressed
        , Keyboard.downs KeyDowns
        ]


view : Model -> Html Msg
view model =
    Html.div [ class "page" ]
        [ Html.map TopBarMsg (NewTopBar.view model.topBar)
        , dashboardView model
        ]


dashboardView : Model -> Html Msg
dashboardView model =
    let
        mainContent =
            case model.state of
                Err NotAsked ->
                    Html.text ""

                Err (Turbulence path) ->
                    turbulenceView path

                Err NoPipelines ->
                    Html.map (always Noop) NoPipeline.view

                Ok substate ->
                    Html.map BodyMsg (Html.div [] [ DashboardBody.view substate.body ])
    in
    Html.div
        [ classList [ ( "dashboard", True ), ( "dashboard-hd", model.highDensity ) ] ]
        [ mainContent ]


noResultsView : String -> Html Msg
noResultsView query =
    let
        boldedQuery =
            Html.span [ class "monospace-bold" ] [ Html.text query ]
    in
    Html.div
        [ class "dashboard" ]
        [ Html.div [ class "dashboard-content " ]
            [ Html.div
                [ class "dashboard-team-group" ]
                [ Html.div [ class "pin-wrapper" ]
                    [ Html.div [ class "dashboard-team-name no-results" ]
                        [ Html.text "No results for "
                        , boldedQuery
                        , Html.text " matched your search."
                        ]
                    ]
                ]
            ]
        ]


helpView : Details.Details -> Html Msg
helpView details =
    Html.div
        [ classList
            [ ( "keyboard-help", True )
            , ( "hidden", not details.showHelp )
            ]
        ]
        [ Html.div [ class "help-title" ] [ Html.text "keyboard shortcuts" ]
        , Html.div [ class "help-line" ] [ Html.div [ class "keys" ] [ Html.span [ class "key" ] [ Html.text "/" ] ], Html.text "search" ]
        , Html.div [ class "help-line" ] [ Html.div [ class "keys" ] [ Html.span [ class "key" ] [ Html.text "?" ] ], Html.text "hide/show help" ]
        ]


toggleView : Bool -> Html Msg
toggleView highDensity =
    let
        hdClass =
            if highDensity then
                "hd-on"

            else
                "hd-off"

        route =
            if highDensity then
                Routes.dashboardRoute

            else
                Routes.dashboardHdRoute
    in
    Html.a [ class "toggle-high-density", href route, ariaLabel "Toggle high-density view" ]
        [ Html.div [ class <| "dashboard-pipeline-icon " ++ hdClass ] [], Html.text "high-density" ]


footerView : SubState.SubState -> Html Msg
footerView substate =
    let
        showHelp =
            substate.details |> Maybe.map .showHelp |> Maybe.withDefault False
    in
    Html.div [] <|
        [ Html.div
            [ if substate.hideFooter || showHelp then
                class "dashboard-footer hidden"

              else
                class "dashboard-footer"
            ]
            [ Html.div [ class "dashboard-legend" ]
                [ Html.div [ class "dashboard-status-pending" ]
                    [ Html.div [ class "dashboard-pipeline-icon" ] [], Html.text "pending" ]
                , Html.div [ class "dashboard-paused" ]
                    [ Html.div [ class "dashboard-pipeline-icon" ] [], Html.text "paused" ]
                , Html.div [ class "dashboard-running" ]
                    [ Html.div [ class "dashboard-pipeline-icon" ] [], Html.text "running" ]
                , Html.div [ class "dashboard-status-failed" ]
                    [ Html.div [ class "dashboard-pipeline-icon" ] [], Html.text "failing" ]
                , Html.div [ class "dashboard-status-errored" ]
                    [ Html.div [ class "dashboard-pipeline-icon" ] [], Html.text "errored" ]
                , Html.div [ class "dashboard-status-aborted" ]
                    [ Html.div [ class "dashboard-pipeline-icon" ] [], Html.text "aborted" ]
                , Html.div [ class "dashboard-status-succeeded" ]
                    [ Html.div [ class "dashboard-pipeline-icon" ] [], Html.text "succeeded" ]
                , Html.div [ class "dashboard-status-separator" ] [ Html.text "|" ]
                , Html.div [ class "dashboard-high-density" ] [ substate.details |> Maybe.Extra.isJust |> not |> toggleView ]
                ]
            , Html.div [ class "concourse-info" ]
                [ Html.div [ class "concourse-version" ]
                    [ Html.text "version: v", substate.version |> Html.text ]
                , Html.div [ class "concourse-cli" ]
                    [ Html.text "cli: "
                    , Html.a [ href (Concourse.Cli.downloadUrl "amd64" "darwin"), ariaLabel "Download OS X CLI" ]
                        [ Html.i [ class "fa fa-apple" ] [] ]
                    , Html.a [ href (Concourse.Cli.downloadUrl "amd64" "windows"), ariaLabel "Download Windows CLI" ]
                        [ Html.i [ class "fa fa-windows" ] [] ]
                    , Html.a [ href (Concourse.Cli.downloadUrl "amd64" "linux"), ariaLabel "Download Linux CLI" ]
                        [ Html.i [ class "fa fa-linux" ] [] ]
                    ]
                ]
            ]
        , Html.div
            [ classList
                [ ( "keyboard-help", True )
                , ( "hidden", not showHelp )
                ]
            ]
            [ Html.div [ class "help-title" ] [ Html.text "keyboard shortcuts" ]
            , Html.div [ class "help-line" ] [ Html.div [ class "keys" ] [ Html.span [ class "key" ] [ Html.text "/" ] ], Html.text "search" ]
            , Html.div [ class "help-line" ] [ Html.div [ class "keys" ] [ Html.span [ class "key" ] [ Html.text "?" ] ], Html.text "hide/show help" ]
            ]
        ]


turbulenceView : String -> Html Msg
turbulenceView path =
    Html.div
        [ class "error-message" ]
        [ Html.div [ class "message" ]
            [ Html.img [ src path, class "seatbelt" ] []
            , Html.p [] [ Html.text "experiencing turbulence" ]
            , Html.p [ class "explanation" ] []
            ]
        ]


handleKeyPressed : Char -> Model -> ( Model, Cmd Msg )
handleKeyPressed key model =
    case key of
        '/' ->
            ( model, Task.attempt (always Noop) (Dom.focus "search-input-field") )

        '?' ->
            model
                |> Monocle.Optional.modify (substateOptional => SubState.detailsOptional) Details.toggleHelp
                |> noop

        _ ->
            update ShowFooter model


fetchData : Cmd Msg
fetchData =
    Group.remoteData
        |> Task.andThen remoteUser
        |> Task.map2 (,) Time.now
        |> RemoteData.asCmd
        |> Cmd.map APIDataFetched


remoteUser : Group.APIData -> Task.Task Http.Error ( Group.APIData, Maybe Concourse.User )
remoteUser d =
    Concourse.User.fetchUser
        |> Task.map ((,) d << Just)
        |> Task.onError (always <| Task.succeed <| ( d, Nothing ))


getCurrentTime : Cmd Msg
getCurrentTime =
    Task.perform ClockTick Time.now
