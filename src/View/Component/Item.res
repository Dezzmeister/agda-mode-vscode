open React

type t =
  | Labeled(string, string, RichText.t, option<string>, option<Common.AgdaRange.t>) // label // style // body // raw string // range
  | Unlabeled(RichText.t, option<string>, option<Common.AgdaRange.t>) // body // raw string // range
  | Header(string) // <h1>

let plainText = s => Unlabeled(RichText.string(s), None, None)
let error = (s, raw) => Labeled("Error", "error", s, raw, None)
let warning = (s, raw) => Labeled("Warning", "warning", s, raw, None)

@react.component
let make = (~item: t) => {
  let (revealRaw, setRevealRaw) = React.useState(_ => false)

  let onClickRevealRaw = _ => setRevealRaw(state => !state)

  let content = (value, raw) =>
    switch raw {
    | Some(raw) => revealRaw ? <RichText value={RichText.string(raw)} /> : <RichText value />
    | None => <RichText value />
    }
  let revealRawButton = raw =>
    switch raw {
    | Some(_) =>
      revealRaw
        ? <div className="item-raw-button active" onClick=onClickRevealRaw>
            <div className="codicon codicon-code" />
          </div>
        : <div className="item-raw-button" onClick=onClickRevealRaw>
            <div className="codicon codicon-code" />
          </div>
    | None => <> </>
    }
  let locationButton = location =>
    switch location {
    | Some(location) =>
      <Link className=["item-location-button"] jump=true hover=false target=Link.SrcLoc(location)>
        <div className="codicon codicon-link" />
      </Link>
    | None => <> </>
    }
  switch item {
  | Labeled(label, style, text, raw, _range) =>
    <li className={"labeled-item " ++ style}>
      <div className="item-label"> {string(label)} </div>
      <div className="item-content"> {content(text, raw)} </div>
      {revealRawButton(raw)}
    </li>
  | Unlabeled(text, raw, range) =>
    <li className="unlabeled-item">
      <div className="item-content"> {content(text, raw)} </div>
      {revealRawButton(raw)}
      {locationButton(range)}
    </li>
  // | HorizontalRule => <li className="horizontalRule-item"></li>
  | Header(s) =>
    <li className="header-item">
      <h3> {string(s)} </h3>
    </li>
  }
}

let decode = {
  open! JsonCombinators.Json.Decode
  Util.Decode.sum(x =>
    switch x {
    | "Labeled" =>
      Payload(
        Util.Decode.tuple5(
          RichText.decode,
          option(string),
          JsonCombinators.Json.Decode.option(Common.AgdaRange.decode),
          string,
          string,
        )->map(((text, raw, range, label, style)) => Labeled(label, style, text, raw, range)),
      )
    | "Unlabeled" =>
      Payload(
        tuple3(
          RichText.decode,
          option(string),
          JsonCombinators.Json.Decode.option(Common.AgdaRange.decode),
        )->map(((text, raw, range)) => Unlabeled(text, raw, range)),
      )
    | "Header" => Payload(string->map(s => Header(s)))
    | tag => raise(DecodeError("[Item] Unknown constructor: " ++ tag))
    }
  )
}

let encode = {
  open! JsonCombinators.Json.Encode
  Util.Encode.sum(x =>
    switch x {
    | Labeled(label, style, text, raw, range) =>
      Payload((
        "Labeled",
        Util.Encode.tuple5(
          RichText.encode,
          option(string),
          option(Common.AgdaRange.encode),
          string,
          string,
          (text, raw, range, label, style),
        ),
      ))
    | Unlabeled(text, raw, range) =>
      Payload((
        "Unlabeled",
        tuple3(RichText.encode, option(string), option(Common.AgdaRange.encode))((
          text,
          raw,
          range,
        )),
      ))
    | Header(s) => Payload(("Header", string(s)))
    }
  , ...)
}
