let str = React.string

let ts = I18n.t(~scope="shared.notifications")
let tr = I18n.t(~scope="components.SchoolCommunities__Editor")

open SchoolCommunities__IndexTypes

module CreateCommunityQuery = %graphql(`
  mutation CreateCommunityMutation($name: String!, $targetLinkable: Boolean!, $courseIds: [ID!]!) {
    createCommunity(name: $name, targetLinkable: $targetLinkable, courseIds: $courseIds ) {
      id
    }
  }
`)

module UpdateCommunityQuery = %graphql(`
  mutation UpdateCommunityMutation($id: ID!, $name: String!, $targetLinkable: Boolean!, $courseIds: [ID!]!) {
    updateCommunity(id: $id, name: $name, targetLinkable: $targetLinkable, courseIds: $courseIds)  {
      communityId
    }
  }
`)

type state = {
  saving: bool,
  dirty: bool,
  name: string,
  targetLinkable: bool,
  selectedCourseIds: Belt.Set.String.t,
  courseSearch: string,
}

let computeInitialState = community => {
  let (name, targetLinkable, selectedCourseIds) = switch community {
  | Some(community) => (
      community |> Community.name,
      community |> Community.targetLinkable,
      Community.courseIds(community) |> Belt.Set.String.fromArray,
    )
  | None => ("", false, Belt.Set.String.empty)
  }

  {
    saving: false,
    dirty: false,
    name: name,
    targetLinkable: targetLinkable,
    selectedCourseIds: selectedCourseIds,
    courseSearch: "",
  }
}

type action =
  | UpdateName(string)
  | SetTargetLinkable(bool)
  | SelectCourse(string)
  | DeselectCourse(string)
  | BeginSaving
  | FailSaving
  | FinishSaving
  | UpdateCourseSearch(string)

let reducer = (state, action) =>
  switch action {
  | UpdateName(name) => {...state, name: name, dirty: true}
  | SetTargetLinkable(targetLinkable) => {
      ...state,
      targetLinkable: targetLinkable,
      dirty: true,
    }
  | SelectCourse(courseId) => {
      ...state,
      dirty: true,
      selectedCourseIds: state.selectedCourseIds->Belt.Set.String.add(courseId),
    }
  | DeselectCourse(courseId) => {
      ...state,
      dirty: true,
      selectedCourseIds: state.selectedCourseIds->Belt.Set.String.remove(courseId),
    }
  | BeginSaving => {...state, saving: true}
  | FailSaving => {...state, saving: false}
  | FinishSaving => {...state, saving: false, dirty: false}
  | UpdateCourseSearch(courseSearch) => {...state, courseSearch: courseSearch}
  }

let handleQuery = (community, state, send, addCommunityCB, updateCommunitiesCB, event) => {
  event |> ReactEvent.Mouse.preventDefault

  let {name, targetLinkable} = state
  let courseIds = state.selectedCourseIds |> Belt.Set.String.toArray

  if name != "" {
    send(BeginSaving)

    switch community {
    | Some(community) =>
      UpdateCommunityQuery.make(
        ~id=community |> Community.id,
        ~name,
        ~targetLinkable,
        ~courseIds,
        (),
      )
      |> GraphqlQuery.sendQuery
      |> Js.Promise.then_(response => {
        let communityId = response["updateCommunity"]["communityId"]
        let topicCategories = Community.topicCategories(community)
        switch communityId {
        | Some(id) =>
          updateCommunitiesCB(
            Community.create(~id, ~name, ~targetLinkable, ~topicCategories, ~courseIds),
          )
          send(FinishSaving)
        | None => send(FinishSaving)
        }

        Notification.success(ts("success"), ts("community_updated"))
        Js.Promise.resolve()
      })
      |> ignore
    | None =>
      CreateCommunityQuery.make(~name, ~targetLinkable, ~courseIds, ())
      |> GraphqlQuery.sendQuery
      |> Js.Promise.then_(response => {
        switch response["createCommunity"]["id"] {
        | Some(id) =>
          let newCommunity = Community.create(
            ~id,
            ~name,
            ~targetLinkable,
            ~topicCategories=[],
            ~courseIds,
          )
          addCommunityCB(newCommunity)
          send(FinishSaving)
        | None => send(FinishSaving)
        }
        Js.Promise.resolve()
      })
      |> Js.Promise.catch(error => {
        Js.log(error)
        Notification.error(
          ts("unexpected_error"),
          tr("notification_reload_post"),
        )
        Js.Promise.resolve()
      })
      |> ignore
    }
  } else {
    Notification.error(ts("empty"), tr("notification_answer_cant_blank"))
  }
}

let booleanButtonClasses = bool => {
  let classes = "toggle-button__button"
  classes ++ (bool ? " toggle-button__button--active" : "")
}

module Selectable = {
  type t = Course.t
  let value = t => t |> Course.name
  let searchString = value
}

module CourseSelector = MultiselectInline.Make(Selectable)

let selectedCourses = (~invert=false, courses, selectedCourseIds) =>
  courses
  |> Array.of_list
  |> Js.Array.filter(course => {
    let condition = selectedCourseIds->Belt.Set.String.has(course |> Course.id)
    invert ? !condition : condition
  })

let unselectedCourses = (courses, selectedCourseIds) =>
  selectedCourses(~invert=true, courses, selectedCourseIds)

let onChangeCourseSearch = (send, value) => send(UpdateCourseSearch(value))

let onSelectCourse = (send, course) => send(SelectCourse(course |> Course.id))

let onDeselectCourse = (send, course) => send(DeselectCourse(course |> Course.id))

let categoryList = categories =>
  ReactUtils.nullIf(
    <div className="mb-2 flex flex-wrap">
      {categories
      |> Js.Array.map(category => {
        let (backgroundColor, color) = Category.color(category)
        <span
          key={category |> Category.id}
          className="border rounded mt-2 mr-2 px-2 py-1 text-xs font-semibold"
          style={ReactDOM.Style.make(~backgroundColor, ~color, ())}>
          {Category.name(category) |> str}
        </span>
      })
      |> React.array}
    </div>,
    ArrayUtils.isEmpty(categories),
  )

@react.component
let make = (
  ~courses,
  ~community,
  ~addCommunityCB,
  ~showCategoryEditorCB,
  ~categories,
  ~updateCommunitiesCB,
) => {
  let (state, send) = React.useReducerWithMapState(reducer, community, computeInitialState)

  let saveDisabled = state.name |> String.trim == "" || !state.dirty

  <div className="mx-8 pt-8">
    <h5 className="uppercase text-center border-b border-gray-400 pb-2">
      {tr("community_editor") |> str}
    </h5>
    <DisablingCover disabled=state.saving>
      <div key="communities-editor" className="mt-3">
        <div className="mt-2">
          <label
            className="inline-block tracking-wide text-gray-700 text-xs font-semibold"
            htmlFor="communities-editor__name">
            {tr("community_editor_label") |> str}
          </label>
          <input
            placeholder=tr("community_editor_placeholder")
            value=state.name
            onChange={event => {
              let name = ReactEvent.Form.target(event)["value"]
              send(UpdateName(name))
            }}
            id="communities-editor__name"
            className="appearance-none h-10 mt-2 block w-full text-gray-700 border border-gray-400 rounded py-2 px-4 text-sm bg-gray-100 hover:bg-gray-200 focus:outline-none focus:bg-white focus:border-primary-400"
          />
          <School__InputGroupError
            message=tr("community_editor_error")
            active={state.dirty ? state.name |> String.trim == "" : false}
          />
        </div>
        <div className="flex items-center mt-6">
          <label
            className="inline-block tracking-wide text-gray-700 text-xs font-semibold"
            htmlFor="communities-editor__course-list">
            {tr("allowed_targets_q") |> str}
          </label>
          <div className="flex toggle-button__group flex-no-shrink rounded-lg overflow-hidden ml-2">
            <button
              onClick={_ => send(SetTargetLinkable(true))}
              className={booleanButtonClasses(state.targetLinkable)}>
              {ts("_yes") |> str}
            </button>
            <button
              onClick={_ => send(SetTargetLinkable(false))}
              className={booleanButtonClasses(!state.targetLinkable)}>
              {ts("_no") |> str}
            </button>
          </div>
        </div>
        <div className="mt-4">
          <label
            className="inline-block tracking-wide text-gray-700 text-xs font-semibold mb-2"
            htmlFor="communities-editor__course-targetLinkable">
            {tr("give_access") |> str}
          </label>
          <CourseSelector
            placeholder=tr("search_course")
            emptySelectionMessage=tr("search_course_empty")
            allItemsSelectedMessage=tr("search_course_all")
            selected={selectedCourses(courses, state.selectedCourseIds)}
            unselected={unselectedCourses(courses, state.selectedCourseIds)}
            onChange={onChangeCourseSearch(send)}
            value=state.courseSearch
            onSelect={onSelectCourse(send)}
            onDeselect={onDeselectCourse(send)}
          />
        </div>
        <div className="mt-4 px-6 py-2 bg-gray-100 border rounded">
          <div className="flex justify-between items-center mb-4">
            <label
              className="inline-block tracking-wide text-gray-700 text-xs font-semibold uppercase">
              {tr("topic_categories") |> str}
            </label>
            {switch community {
            | Some(_community) =>
              <button
                onClick={_ => showCategoryEditorCB()}
                className="flex items-center justify-center relative bg-white text-primary-500 hover:bg-gray-100 hover:text-primary-600 hover:shadow-lg focus:outline-none border border-gray-400 hover:border-primary-300 p-2 rounded-lg cursor-pointer">
                <i className="fas fa-pencil-alt" />
                <span className="text-xs font-semibold ml-2">
                  {(ArrayUtils.isEmpty(categories) ? tr("add_categories") : tr("edit_categories")) |> str}
                </span>
              </button>
            | None => React.null
            }}
          </div>
          {switch community {
          | Some(_community) =>
            categories |> ArrayUtils.isEmpty
              ? <p className="text-xs text-gray-800">
                  {tr("no_topic") |> str}
                </p>
              : categoryList(categories)
          | None =>
            <p className="text-xs text-gray-800">
              {tr("can_add_topic") |> str}
            </p>
          }}
        </div>
      </div>
      <button
        disabled=saveDisabled
        onClick={handleQuery(community, state, send, addCommunityCB, updateCommunitiesCB)}
        key="communities-editor__update-button"
        className="w-full btn btn-large btn-primary mt-3">
        {switch community {
        | Some(_) => tr("update_community")
        | None => tr("create_community")
        } |> str}
      </button>
    </DisablingCover>
    <div className="mt-3 mb-3 text-xs">
      <span className="leading-normal">
        <strong> {I18n.t("shared.note") |> str} </strong>
        {I18n.t("communities.note") |> str}
      </span>
    </div>
  </div>
}
