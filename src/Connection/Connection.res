module Error = Connection__Error
module Agda = Connection__Target__Agda
module ALS = Connection__Target__ALS
module Target = Connection__Target
module URI = Connection__URI

module type Module = {
  // lifecycle
  let start: State__Type.t => promise<result<unit, Error.t>>
  let stop: unit => promise<result<unit, Error.t>>
  // messaging
  let sendRequest: (
    State__Type.t,
    Request.t,
    result<Response.t, Error.t> => promise<unit>,
  ) => promise<result<Target.t, Error.t>>

  //
  let findCommand: string => promise<result<unit, Error.t>>

  // misc
  let makeAgdaLanguageServerRepo: (
    State__Type.Memento.t,
    string,
  ) => Connection__Download__GitHub.Repo.t
  let getALSReleaseManifest: State__Type.t => promise<
    result<array<Connection__Download__GitHub.Release.t>, Error.t>,
  >
}

module Module: Module = {
  module InitOptions = {
    type t = {commandLineOptions: array<string>}

    let encode = ({commandLineOptions}) => {
      open JsonCombinators.Json.Encode
      Unsafe.object({
        "commandLineOptions": array(string)(commandLineOptions),
      })
    }

    let getFromConfig = () =>
      {
        commandLineOptions: Config.Connection.getCommandLineOptions(),
      }->encode
  }

  // internal state singleton
  type t = Agda(Agda.t, Target.t) | ALS(ALS.t, Target.t)
  let singleton: ref<option<t>> = ref(None)

  let stop = async () =>
    switch singleton.contents {
    | None => Ok()
    | Some(Agda(conn, _)) =>
      singleton := None
      await Agda.destroy(conn)
      Ok()
    | Some(ALS(conn, _)) =>
      singleton := None
      switch await ALS.destroy(conn) {
      | Error(error) => Error(Error.ALS(error))
      | Ok(_) => Ok()
      }
    }

  let start_ = async (target: Target.t): result<unit, Error.t> =>
    switch target {
    | Agda(version, path) =>
      let method = Connection__IPC.ViaPipe(path, [], None, FromFile(path))
      switch await Agda.make(method) {
      | Error(error) => Error(Error.Agda(error, path))
      | Ok(conn) =>
        singleton := Some(Agda(conn, Agda(version, path)))
        Ok()
      }
    | ALS(alsVersion, agdaVersion, Ok(method)) =>
      switch await ALS.make(method, InitOptions.getFromConfig()) {
      | Error(error) => Error(ALS(error))
      | Ok(conn) =>
        let method = ALS.getIPCMethod(conn)
        singleton := Some(ALS(conn, ALS(alsVersion, agdaVersion, Ok(method))))
        Ok()
      }
    | ALS(alsVersion, agdaVersion, Error(path)) =>
      switch await ALS.make(
        Connection__IPC.ViaPipe(path, [], None, FromFile(path)),
        InitOptions.getFromConfig(),
      ) {
      | Error(error) => Error(ALS(error))
      | Ok(conn) =>
        // let method = ALS.getIPCMethod(conn)
        singleton := Some(ALS(conn, ALS(alsVersion, agdaVersion, Error(path))))
        Ok()
      }
    }

  let findCommand = async command => {
    switch await Connection__Command.search(command) {
    | Error(error) => Error(Error.CannotFindCommand(command, error))
    | Ok(path) =>
      switch await Target.fromRawPath(path) {
      | Error(error) => Error(error)
      | Ok(target) =>
        await Config.Connection.addAgdaPath(path)
        await start_(target)
      }
    }
  }

  let findALSAndAgda = async () => {
    switch await findCommand("agda") {
    | Error(_error) => await findCommand("als")
    | Ok() => Ok()
    }
  }

  let start = async state =>
    switch singleton.contents {
    | Some(_) => Ok()
    | None =>
      switch await Target.getPicked(state) {
      | None => await findALSAndAgda()
      | Some(target) => await start_(target)
      }
    }
  let rec sendRequest = async (
    state: State__Type.t,
    // globalStorageUri,
    // onDownload,
    // useALS,
    request,
    handler,
  ) => {
    // encode the Request to some string
    let encodeRequest = (document, version) => {
      let filepath = document->VSCode.TextDocument.fileName->Parser.filepath
      let libraryPath = Config.getLibraryPath()
      let highlightingMethod = Config.Highlighting.getHighlightingMethod()
      let backend = Config.getBackend()
      Request.encode(document, version, filepath, backend, libraryPath, highlightingMethod, request)
    }

    switch singleton.contents {
    | Some(ALS(conn, target)) =>
      let handler = x => x->Util.Result.mapError(err => Error.ALS(err))->handler
      switch await ALS.sendRequest(conn, encodeRequest(state.document, conn.agdaVersion), handler) {
      | Error(error) =>
        // stop the connection on error
        let _ = await stop()
        Error(Error.ALS(error))
      | Ok(_) => Ok(target)
      }

    | Some(Agda(conn, target)) =>
      let (version, path) = Agda.getInfo(conn)
      let handler = x => x->Util.Result.mapError(err => Error.Agda(err, path))->handler
      switch await Agda.sendRequest(conn, encodeRequest(state.document, version), handler) {
      | Error(error) =>
        // stop the connection on error
        let _ = await stop()
        Error(Error.Agda(error, path))
      | Ok(_) => Ok(target)
      }
    | None =>
      switch await start(state) {
      | Error(error) => Error(error)
      | Ok(_) => await sendRequest(state, request, handler)
      }
    }
  }

  let makeAgdaLanguageServerRepo: (
    State__Type.Memento.t,
    string,
  ) => Connection__Download__GitHub.Repo.t = (memento, globalStoragePath) => {
    username: "agda",
    repository: "agda-language-server",
    userAgent: "agda/agda-mode-vscode",
    memento,
    globalStoragePath,
    cacheInvalidateExpirationSecs: 86400,
  }

  let getALSReleaseManifest = async (state: State__Type.t) => {
    switch await Connection__Download__GitHub.ReleaseManifest.fetch(
      makeAgdaLanguageServerRepo(state.memento, VSCode.Uri.fsPath(state.globalStorageUri)),
    ) {
    | (Error(error), _) => Error(Error.CannotFetchALSReleases(error))
    | (Ok(manifest), _) => Ok(manifest)
    }
  }
}

include Module
