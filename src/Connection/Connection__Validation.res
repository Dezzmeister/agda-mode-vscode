// module for validating a given path
module Error = {
  type t =
    | PathMalformed(string)
    | // the process has not been responding for some time
    ProcessHanging
    // error from the shell
    | NotFound(string)
    | ShellError(Js.Exn.t)
    // error from the process' stderr
    | ProcessError(string)
    // wrong invoked command
    | WrongProcess(string)
  let toString = x =>
    switch x {
    | PathMalformed(msg) => "path malformed: " ++ msg
    | ProcessHanging => "process hanging for more than 1 sec"

    | NotFound(error) => error
    | ShellError(error) => "shell: " ++ Util.JsError.toString(error)
    | ProcessError(msg) => "stderr: " ++ msg
    | WrongProcess(msg) => "wrong process: " ++ msg
    }
}

type output = string
type validator<'a> = output => result<'a, string>

let run = (path, args, validator: validator<'a>): promise<result<'a, Error.t>> => {
  // parsing the parse error
  let parseError = (error: Js.nullable<Js.Exn.t>): option<Error.t> =>
    error
    ->Js.Nullable.toOption
    ->Option.map(err => {
      let message = Option.getOr(Js.Exn.message(err), "")
      if Js.Re.test_(%re("/No such file or directory/"), message) {
        Error.NotFound(message)
      } else if (
        Js.Re.test_(%re("/command not found/"), message) || String.endsWith(message, "ENOENT")
      ) {
        NotFound(message)
      } else {
        ShellError(err)
      }
    })

  Promise.make((resolve, _) => {
    // the path must not be empty
    if path == "" {
      resolve(Error(Error.PathMalformed("the path must not be empty")))
    }

    // reject if the process hasn't responded for more than 20 second
    let hangTimeout = Js.Global.setTimeout(() => resolve(Error(ProcessHanging)), 20000)

    // clear timeout as the process has responded

    // parses `error` and rejects it if there's any

    // stderr

    // feed the stdout to the validator

    ignore(
      NodeJs.ChildProcess.execFile(path, args, (error, stdout, stderr) => {
        Js.Global.clearTimeout(hangTimeout)

        parseError(error)->Belt.Option.forEach(err => resolve(Error(err)))

        let stderr = NodeJs.Buffer.toString(stderr)
        if stderr != "" {
          resolve(Error(ProcessError(stderr)))
        }

        let stdout = NodeJs.Buffer.toString(stdout)
        switch validator(stdout) {
        | Error(err) => resolve(Error(WrongProcess(err)))
        | Ok(result) => resolve(Ok(result))
        }
      }),
    )
  })
}
