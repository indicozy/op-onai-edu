open StudentsEditor__Types

let tr = I18n.t(~scope="components.StudentEditor__UpdateDetailsForm")
let ts = I18n.ts

type rec teamCoachlist = (coachId, coachName, selected)
and coachId = string
and coachName = string
and selected = bool

type state = {
  name: string,
  teamName: string,
  userTags: array<string>,
  tagsToApply: array<string>,
  teamCoaches: array<string>,
  teamCoachSearchInput: string,
  title: string,
  affiliation: string,
  saving: bool,
  accessEndsAt: option<Js.Date.t>,
}

type action =
  | UpdateName(string)
  | UpdateTeamName(string)
  | AddTag(string)
  | RemoveTag(string)
  | UpdateCoachesList(array<string>)
  | UpdateCoachSearchInput(string)
  | UpdateTitle(string)
  | UpdateAffiliation(string)
  | UpdateSaving(bool)
  | UpdateAccessEndsAt(option<Js.Date.t>)

let str = React.string

let stringInputInvalid = s => s |> String.length < 2

let updateName = (send, name) => send(UpdateName(name))

let updateTeamName = (send, teamName) => send(UpdateTeamName(teamName))

let updateTitle = (send, title) => send(UpdateTitle(title))

let formInvalid = state =>
  state.name |> stringInputInvalid ||
    (state.teamName |> stringInputInvalid ||
    state.title |> stringInputInvalid)

let handleErrorCB = (send, ()) => send(UpdateSaving(false))

let successMessage = (accessEndsAt, isSingleFounder) =>
  switch accessEndsAt {
  | Some(date) =>
    switch (date->DateFns.isPast, isSingleFounder) {
    | (true, true) => tr("student_updated_moved")
    | (true, false) => tr("team_updated_moved")
    | (false, true)
    | (false, false) => tr("student_updated")
    }
  | None => tr("student_updated")
  }

let enrolledCoachIds = teamCoaches =>
  teamCoaches
  |> Js.Array.filter(((_, _, selected)) => selected == true)
  |> Array.map(((key, _, _)) => key)

let handleResponseCB = (updateFormCB, state, student, oldTeam, _json) => {
  let affiliation = switch state.affiliation |> String.trim {
  | "" => None
  | text => Some(text)
  }
  let newStudent = Student.update(~name=state.name, ~title=state.title, ~affiliation, ~student)
  let newTeam = Team.update(
    ~name=state.teamName,
    ~teamTags=state.tagsToApply,
    ~student=newStudent,
    ~coachIds=state.teamCoaches,
    ~accessEndsAt=state.accessEndsAt,
    ~team=oldTeam,
  )

  // Remove inactive teams from the list
  let team = newTeam |> Team.active ? Some(newTeam) : None

  updateFormCB(state.tagsToApply, team)
  Notification.success(
    ts("notifications.success"),
    successMessage(state.accessEndsAt, newTeam |> Team.isSingleStudent),
  )
}

let updateStudent = (student, state, send, responseCB) => {
  send(UpdateSaving(true))
  let payload = Js.Dict.empty()

  Js.Dict.set(payload, "authenticity_token", AuthenticityToken.fromHead() |> Js.Json.string)

  let updatedStudent = Student.updateInfo(
    ~name=state.name,
    ~title=state.title,
    ~affiliation=Some(state.affiliation),
    ~student,
  )
  Js.Dict.set(payload, "founder", Student.encode(state.teamName, updatedStudent))
  Js.Dict.set(
    payload,
    "tags",
    state.tagsToApply |> {
      open Json.Encode
      array(string)
    },
  )
  Js.Dict.set(
    payload,
    "coach_ids",
    state.teamCoaches |> {
      open Json.Encode
      array(string)
    },
  )

  Js.Dict.set(
    payload,
    "access_ends_at",
    state.accessEndsAt->Belt.Option.mapWithDefault(Json.Encode.string(""), DateFns.encodeISO),
  )

  let url = "/school/students/" ++ (student |> Student.id)
  Api.update(url, payload, responseCB, handleErrorCB(send))
}

let boolBtnClasses = selected => {
  let classes = "toggle-button__button"
  classes ++ (selected ? " toggle-button__button--active" : "")
}

let handleTeamCoachList = (schoolCoaches, team) => {
  let selectedTeamCoachIds = team |> Team.coachIds
  schoolCoaches |> Array.map(coach => {
    let coachId = coach |> Coach.id
    let selected =
      selectedTeamCoachIds |> Js.Array.findIndex(selectedCoachId => coachId == selectedCoachId) > -1

    (coach |> Coach.id, coach |> Coach.name, selected)
  })
}

module SelectablePrerequisiteTargets = {
  type t = Coach.t

  let value = t => t |> Coach.name
  let searchString = value

  let make = (coach): t => coach
}

let setTeamCoachSearch = (send, value) => send(UpdateCoachSearchInput(value))

let selectTeamCoach = (send, state, coach) => {
  let updatedTeamCoaches = state.teamCoaches |> Js.Array.concat([coach |> Coach.id])
  send(UpdateCoachesList(updatedTeamCoaches))
}

let deSelectTeamCoach = (send, state, coach) => {
  let updatedTeamCoaches =
    state.teamCoaches |> Js.Array.filter(coachId => coachId != Coach.id(coach))
  send(UpdateCoachesList(updatedTeamCoaches))
}

module MultiselectForTeamCoaches = MultiselectInline.Make(SelectablePrerequisiteTargets)

let teamCoachesEditor = (courseCoaches, state, send) => {
  let selected =
    courseCoaches
    |> Js.Array.filter(coach => state.teamCoaches |> Array.mem(Coach.id(coach)))
    |> Array.map(coach => SelectablePrerequisiteTargets.make(coach))

  let unselected =
    courseCoaches
    |> Js.Array.filter(coach => !(state.teamCoaches |> Array.mem(Coach.id(coach))))
    |> Array.map(coach => SelectablePrerequisiteTargets.make(coach))
  <div className="mt-2">
    <MultiselectForTeamCoaches
      placeholder=tr("search_coaches_placeholder")
      emptySelectionMessage=tr("search_coaches_empty")
      allItemsSelectedMessage=tr("search_coaches_all")
      selected
      unselected
      onChange={setTeamCoachSearch(send)}
      value=state.teamCoachSearchInput
      onSelect={selectTeamCoach(send, state)}
      onDeselect={deSelectTeamCoach(send, state)}
    />
  </div>
}

let initialState = (student, team) => {
  name: student |> Student.name,
  teamName: team |> Team.name,
  userTags: student |> Student.userTags,
  tagsToApply: team |> Team.tags,
  teamCoaches: team |> Team.coachIds,
  teamCoachSearchInput: "",
  title: student |> Student.title,
  affiliation: student |> Student.affiliation |> OptionUtils.toString,
  saving: false,
  accessEndsAt: team |> Team.accessEndsAt,
}

let reducer = (state, action) =>
  switch action {
  | UpdateName(name) => {...state, name: name}
  | UpdateTeamName(teamName) => {...state, teamName: teamName}
  | AddTag(tag) => {
      ...state,
      tagsToApply: state.tagsToApply |> Array.append([tag]),
    }
  | RemoveTag(tag) => {
      ...state,
      tagsToApply: state.tagsToApply |> Js.Array.filter(t => t !== tag),
    }
  | UpdateCoachesList(teamCoaches) => {...state, teamCoaches: teamCoaches}
  | UpdateCoachSearchInput(teamCoachSearchInput) => {
      ...state,
      teamCoachSearchInput: teamCoachSearchInput,
    }
  | UpdateTitle(title) => {...state, title: title}
  | UpdateAffiliation(affiliation) => {...state, affiliation: affiliation}
  | UpdateSaving(bool) => {...state, saving: bool}
  | UpdateAccessEndsAt(accessEndsAt) => {...state, accessEndsAt: accessEndsAt}
  }

@react.component
let make = (~student, ~team, ~teamTags, ~courseCoaches, ~updateFormCB) => {
  let (state, send) = React.useReducer(reducer, initialState(student, team))

  let isSingleStudent = team |> Team.isSingleStudent

  <DisablingCover disabled=state.saving>
    <div>
      <div className="pt-5">
        <label
          className="inline-block tracking-wide text-xs font-semibold mb-2 leading-tight"
          htmlFor="name">
          {ts("name") |> str}
        </label>
        <input
          value=state.name
          onChange={event => updateName(send, ReactEvent.Form.target(event)["value"])}
          className="appearance-none block w-full bg-white border border-gray-400 rounded py-3 px-4 leading-snug focus:outline-none focus:bg-white focus:border-gray-500"
          id="name"
          type_="text"
          placeholder=tr("student_name_placeholder")
        />
        <School__InputGroupError
          message="Name must have at least two characters" active={state.name |> stringInputInvalid}
        />
      </div>
      {isSingleStudent
        ? React.null
        : <div className="mt-5">
            <label
              className="inline-block tracking-wide text-xs font-semibold mb-2 leading-tight"
              htmlFor="team_name">
              {ts("team_name") |> str}
            </label>
            <input
              value=state.teamName
              onChange={event => updateTeamName(send, ReactEvent.Form.target(event)["value"])}
              maxLength=50
              className="appearance-none block w-full bg-white border border-gray-400 rounded py-3 px-4 leading-snug focus:outline-none focus:bg-white focus:border-gray-500"
              id="team_name"
              type_="text"
              placeholder=tr("team_name_placeholder")
            />
            <School__InputGroupError
              message=tr("team_name_error")
              active={state.teamName |> stringInputInvalid}
            />
          </div>}
      <div className="mt-5">
        <label
          className="inline-block tracking-wide text-xs font-semibold mb-2 leading-tight"
          htmlFor="title">
          {ts("title") |> str}
        </label>
        <input
          value=state.title
          onChange={event => updateTitle(send, ReactEvent.Form.target(event)["value"])}
          className="appearance-none block w-full bg-white border border-gray-400 rounded py-3 px-4 leading-snug focus:outline-none focus:bg-white focus:border-gray-500"
          id="title"
          type_="text"
          placeholder=ts("title_placeholder")
        />
        <School__InputGroupError
          message=ts("title_error")
          active={state.title |> stringInputInvalid}
        />
      </div>
      <div className="mt-5">
        <label
          className="inline-block tracking-wide text-xs font-semibold mb-2 leading-tight"
          htmlFor="affiliation">
          {ts("affiliation") |> str}
        </label>
        <span className="text-xs ml-1"> {ts("optional_braces") |> str} </span>
        <input
          value=state.affiliation
          onChange={event => send(UpdateAffiliation(ReactEvent.Form.target(event)["value"]))}
          className="appearance-none block w-full bg-white border border-gray-400 rounded py-3 px-4 leading-snug focus:outline-none focus:bg-white focus:border-gray-500"
          id="affiliation"
          type_="text"
          placeholder=ts("affiliation_placeholder")
        />
      </div>
      <div className="mt-5">
        <div className="border-b pb-4 mb-2 mt-5 ">
          <span className="inline-block mr-1 text-xs font-semibold">
            {(isSingleStudent ? tr("personal_coaches") : tr("team_coaches")) |> str}
          </span>
          {teamCoachesEditor(courseCoaches, state, send)}
        </div>
      </div>
      {state.userTags |> ArrayUtils.isNotEmpty
        ? <div className="mt-5">
            <div className="mb-2 text-xs font-semibold"> { tr("tags_applied_user") ++ ":" |> str} </div>
            <div className="flex flex-wrap">
              {state.userTags
              |> Js.Array.map(tag =>
                <div
                  className="bg-blue-100 border border-blue-500 rounded-lg px-2 py-px mt-1 mr-1 text-xs text-gray-900"
                  key={tag}>
                  {str(tag)}
                </div>
              )
              |> React.array}
            </div>
          </div>
        : React.null}
      <div className="mt-5">
        <div className="mb-2 text-xs font-semibold">
          {(isSingleStudent ? tr("tags_applied") : tr("tags_applied_team") ++ ":") |> str}
        </div>
        <School__SearchableTagList
          unselectedTags={teamTags |> Js.Array.filter(tag =>
            !(state.tagsToApply |> Array.mem(tag))
          )}
          selectedTags=state.tagsToApply
          addTagCB={tag => send(AddTag(tag))}
          removeTagCB={tag => send(RemoveTag(tag))}
          allowNewTags=true
        />
      </div>
      <div className="mt-5">
        <label className="tracking-wide text-xs font-semibold" htmlFor="access-ends-at-input">
          {(isSingleStudent ? tr("student_s") : tr("team_s")) ++ " " ++ tr("access_ends") |> str}
        </label>
        <span className="ml-1 text-xs"> {ts("optional_braces") |> str} </span>
        <HelpIcon
          className="ml-2" link="https://docs.pupilfirst.com/#/students?id=editing-student-details">
          {tr("students_not_able_complete_help") |> str}
        </HelpIcon>
        <DatePicker
          onChange={date => send(UpdateAccessEndsAt(date))}
          selected=?state.accessEndsAt
          id="access-ends-at-input"
        />
      </div>
    </div>
    <div className="my-5 w-auto">
      <button
        disabled={formInvalid(state)}
        onClick={_e =>
          updateStudent(student, state, send, handleResponseCB(updateFormCB, state, student, team))}
        className="w-full btn btn-large btn-primary">
        {tr("update_student") |> str}
      </button>
    </div>
  </DisablingCover>
}
