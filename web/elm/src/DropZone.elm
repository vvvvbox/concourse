module DropZone exposing (DropZoneState(..), dragEnter, dropZones, off, view)

import DragEvent
import DragList
import Html exposing (Html)
import Html.Attributes exposing (classList)
import Html.Events exposing (on)
import Json.Decode
import List.Extra
import Maybe.Extra
import RestList


type DropZoneState a
    = On
    | Off { dragEnter : RestList.RestList a }
    | Disabled


off : RestList.RestList a -> DropZoneState a
off restList =
    Off { dragEnter = restList }


dragEnter : DropZoneState a -> Maybe (RestList.RestList a)
dragEnter item =
    case item of
        Off { dragEnter } ->
            Just dragEnter

        _ ->
            Nothing


dropZones : DragList.DragList a -> List (DropZoneState a)
dropZones dragList =
    dragList.initial
        |> RestList.toList
        |> RestList.restLists
        |> List.map off
        |> List.Extra.replaceIf (dragEnter >> (==) (Just dragList.current)) On


view : DropZoneState a -> Html (DragEvent.Msg a)
view dropZoneState =
    case dropZoneState of
        On ->
            view_ True
                [ on "dragleave" (Json.Decode.succeed DragEvent.DragLeave) ]

        Off { dragEnter } ->
            view_ False
                [ on "dragenter" (Json.Decode.succeed (DragEvent.DragEnter dragEnter)) ]

        Disabled ->
            view_ False []


view_ : Bool -> List (Html.Attribute msg) -> Html msg
view_ over dragAttrs =
    Html.div
        (styleAttrs over ++ dragAttrs)
        [ Html.text "" ]


styleAttrs : Bool -> List (Html.Attribute msg)
styleAttrs over =
    [ classList
        [ ( "drop-area", True )
        , ( "active", not over )
        , ( "over", over )
        , ( "animation", over )
        ]
    ]
