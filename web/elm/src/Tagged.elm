module Tagged exposing
    ( Tagged
    , view
    , addTagsAndSort
    )

import Concourse
import Dashboard.Group.Tag as Tag
import Grouped
import Html exposing (Html)
import Html.Attributes exposing (class)
import Ordering exposing (Ordering)


type alias Tagged a =
    { item : a
    , tag : Tag.Tag
    }


addTagsAndSort : Concourse.User -> List (Grouped.Grouped a) -> List (Tagged (Grouped.Grouped a))
addTagsAndSort user =
    List.map (addTag user) >> List.sortWith ordering


addTag : Concourse.User -> Grouped.Grouped a -> Tagged (Grouped.Grouped a)
addTag user group =
    { item = group
    , tag = Tag.tag user group.teamName
    }


ordering : Ordering (Tagged (Grouped.Grouped a))
ordering =
    Ordering.byFieldWith Tag.ordering .tag
        |> Ordering.breakTiesWith (Ordering.byFieldWith Grouped.ordering .item)


view : Tagged (Grouped.Grouped a) -> List (Html msg)
view tagged =
    [ Html.div [ class "dashboard-team-name" ] [ Html.text tagged.item.teamName ]
    , Html.div [ class "dashboard-team-tag" ] [ Html.text <| Tag.text tagged.tag ]
    ]
