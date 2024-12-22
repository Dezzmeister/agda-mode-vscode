// For throttling Requests send to Agda
// 1 Request to Agda at a time
module RequestQueue: {
  type t
  let make: unit => t
  // only gets resolved after the Request has been handled
  let push: (t, Request.t => promise<unit>, Request.t) => promise<unit>
} = {
  type t = {
    queue: array<unit => promise<unit>>,
    mutable busy: bool,
  }

  let make = () => {
    queue: [],
    busy: false,
  }

  let rec kickStart = self =>
    if self.busy {
      // busy running, just leave it be
      ()
    } else {
      // pop the front of the queue
      switch Array.shift(self.queue) {
      | None => () // nothing to pop
      | Some(thunk) =>
        self.busy = true
        thunk()
        ->Promise.finally(_ => {
          self.busy = false
          kickStart(self)
        })
        ->Promise.done
      }
    }

  // only gets resolved after the Request has been handled
  let push = (self, sendRequestAndHandleResponses, request) => {
    let (promise, resolve, _) = Util.Promise_.pending()
    let thunk = async () => {
      await sendRequestAndHandleResponses(request)
      resolve()
    }
    // push to the back of the queue
    self.queue->Array.push(thunk)
    // kick start
    kickStart(self)
    promise
  }
}

// cache the stuff previously displayed in the view, so that we can restore them later
module ViewCache = {
  type t = {
    mutable display: option<(View.Header.t, View.Body.t)>,
    mutable prompt: option<(View.Header.t, View.Prompt.t, View.Response.t => promise<unit>)>,
  }

  let make = () => {
    display: None,
    prompt: None,
  }

  let cacheEvent = (self, event: View.EventToView.t) =>
    switch event {
    // cache the event only when it's a "Display"
    | Display(header, body) => self.display = Some((header, body))
    | _ => ()
    }

  let cacheRequest = (self, event: View.Request.t, callback) =>
    switch event {
    | Prompt(header, prompt) => self.prompt = Some(header, prompt, callback)
    }

  let clearPrompt = self => self.prompt = None

  // if there's no Prompt, then restore Display instead
  let restore = (self, view) =>
    switch self.prompt {
    | Some((header, prompt, callback)) =>
      view->WebviewPanel.sendRequest(Prompt(header, prompt), callback)->ignore
    | None =>
      self.display->Option.forEach(((header, body)) =>
        view->WebviewPanel.sendEvent(Display(header, body))->ignore
      )
    }
}

// datatype for logging
module Log = {
  type t =
    | CommandDispatched(Command.t)
    | CommandHandled(Command.t)
    | RequestSent(Request.t)
    | ResponseHandled(Response.t)
    | Others(string) // generic string

  let toString = log =>
    switch log {
    | CommandDispatched(command) => " <=== " ++ Command.toString(command)
    | RequestSent(request) => "   <- " ++ Request.toString(request)
    | ResponseHandled(response) => "    > " ++ Response.toString(response)
    | CommandHandled(command) => " ===> " ++ Command.toString(command)
    | Others(str) => str
    }
}

// Binds to VSCode.Memento when VSCode.ExtensionContext is available
// Binds to a mock when testing
module Memento: {
  type t
  let make: option<VSCode.Memento.t> => t
  let get: (t, string) => option<'a>
  let getWithDefault: (t, string, 'a) => 'a
  let keys: t => array<string>
  let update: (t, string, 'a) => promise<unit>
} = {
  @unboxed type rec any = Any('x): any

  type t = Memento(VSCode.Memento.t) | Mock(Dict.t<any>)

  let make = memento =>
    switch memento {
    | Some(memento) => Memento(memento)
    | None => Mock(Dict.make())
    }

  let get = (context, key) =>
    switch context {
    | Memento(context) => VSCode.Memento.get(context, key)
    | Mock(dict) => Obj.magic(dict->Dict.get(key))
    }
  let getWithDefault = (context, key, defaultValue) =>
    switch context {
    | Memento(context) => VSCode.Memento.getWithDefault(context, key, defaultValue)
    | Mock(dict) =>
      switch dict->Dict.get(key) {
      | Some(value) => Obj.magic(value)
      | None => defaultValue
      }
    }

  let keys = context =>
    switch context {
    | Memento(context) => VSCode.Memento.keys(context)
    | Mock(dict) => dict->Dict.keysToArray
    }

  let update = (context, key, value) =>
    switch context {
    | Memento(context) => VSCode.Memento.update(context, key, value)
    | Mock(dict) => dict->Dict.set(key, Obj.magic(value))->Promise.resolve
    }
}

type channels = {
  inputMethod: Chan.t<IM.Log.t>,
  // emits when a Response has been handled
  responseHandled: Chan.t<Response.t>,
  // emits when a Command has been handled
  commandHandled: Chan.t<Command.t>,
  // for debugging
  log: Chan.t<Log.t>,
}

type t = {
  mutable agdaVersion: option<string>, // Agda version is set when connection is established
  mutable editor: VSCode.TextEditor.t,
  mutable document: VSCode.TextDocument.t,
  panelCache: ViewCache.t,
  mutable runningInfoLog: array<(int, string)>,
  mutable goals: array<Goal.t>,
  tokens: Tokens.t,
  mutable highlighting: Highlighting.t,
  mutable cursor: option<VSCode.Position.t>,
  editorIM: IM.t,
  promptIM: IM.t,
  mutable subscriptions: array<VSCode.Disposable.t>,
  // for self destruction
  onRemoveFromRegistry: Chan.t<unit>,
  // Agda Request queue
  mutable agdaRequestQueue: RequestQueue.t,
  globalStorageUri: VSCode.Uri.t,
  extensionPath: string,
  memento: Memento.t,
  // for logging and testing
  channels: channels,
}
type state = t

// control the scope of command key-binding
module Context = {
  // input method related key-bindings
  let setPrompt = value => VSCode.Commands.setContext("agdaModePrompting", value)->ignore
  let setIM = value => VSCode.Commands.setContext("agdaModeTyping", value)->ignore
}
