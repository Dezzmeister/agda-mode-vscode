open Mocha
open Test__Util

describe("Connection", () => {
  describe("Target", () => {
    let agdaMockPath = ref("")
    let agdaMockTarget = ref(None)

    Async.before(
      async () => {
        // setup the Agda mock
        agdaMockPath := (await Target.Agda.mock(~version="2.7.0.1", ~name="agda-mock"))

        switch await Connection.Target.fromRawPath(agdaMockPath.contents) {
        | Ok(target) => agdaMockTarget := Some(target)
        | Error(_) => failwith("Got error when trying to construct a mock for Agda ")
        }
      },
    )

    Async.it(
      "should return the previously picked connection",
      async () => {
        // access the Agda mock
        let agdaMockTarget = switch agdaMockTarget.contents {
        | Some(target) => target
        | None => failwith("Unable to access the Agda mock target")
        }

        // setup the momento
        let memento = State__Memento.make(None)
        await Connection.Target.setPicked(memento, Some(agdaMockTarget))

        let paths = [agdaMockPath.contents, "path/to/als"]->Array.map(Connection__URI.parse)

        let actual = await Connection__Target.getPicked(memento, paths)
        let expected = Ok(agdaMockTarget)

        Assert.deepEqual(actual, expected)
      },
    )

    Async.it(
      "should return nothing when there's no previously picked connection",
      async () => {
        // setup the momento
        let memento = State__Memento.make(None)
        let paths = ["path/to/agda", "path/to/als"]->Array.map(Connection__URI.parse)

        let actual = await Connection__Target.getPicked(memento, paths)
        let expected = Error([
          Connection.Error.ValidationError("path/to/agda", NotFound("spawn path/to/agda ENOENT")),
          Connection.Error.ValidationError("path/to/als", NotFound("spawn path/to/als ENOENT")),
        ])

        Assert.deepEqual(actual, expected)
      },
    )

    Async.it(
      "should return nothing when the previously picked connection is not in the supplied paths",
      async () => {
        // access the Agda mock
        let agdaMockTarget = switch agdaMockTarget.contents {
        | Some(target) => target
        | None => failwith("Unable to access the Agda mock target")
        }

        // setup the momento
        let memento = State__Memento.make(None)
        await Connection.Target.setPicked(memento, Some(agdaMockTarget))
        let paths = ["path/to/agda", "path/to/als"]->Array.map(Connection__URI.parse)

        let actual = await Connection__Target.getPicked(memento, paths)
        let expected = Error([
          Connection.Error.ValidationError("path/to/agda", NotFound("spawn path/to/agda ENOENT")),
          Connection.Error.ValidationError("path/to/als", NotFound("spawn path/to/als ENOENT")),
        ])

        Assert.deepEqual(actual, expected)
      },
    )

    Async.it(
      "should return the first usable connection target when the previously picked connection is invalid or not in the supplied paths",
      async () => {
        // access the Agda mock
        let agdaMockTarget = switch agdaMockTarget.contents {
        | Some(target) => target
        | None => failwith("Unable to access the Agda mock target")
        }

        // setup the momento
        let memento = State__Memento.make(None)
        let paths =
          [
            "path/to/non-existent-agda",
            agdaMockPath.contents,
            "path/to/non-existent-als",
          ]->Array.map(Connection__URI.parse)

        let actual = await Connection__Target.getPicked(memento, paths)
        let expected = Ok(agdaMockTarget)

        Assert.deepEqual(actual, expected)
      },
    )

    Async.after(
      async () => {
        // cleanup the Agda mock
        switch agdaMockTarget.contents {
        | Some(target) =>
          Target.Agda.destroy(target)
          agdaMockTarget := None
        | None => ()
        }
      },
    )
  })

  describe("Command searching", () => {
    Async.it(
      "should be able to find itself (`which` or `where`)",
      async () => {
        switch NodeJs.Os.type_() {
        | "Linux"
        | "Darwin" =>
          switch await Connection__Command__Search.search("which") {
          | Ok(_output) => ()
          | Error(_) => failwith("expected to find `which`")
          }
        | "Windows_NT" =>
          switch await Connection__Command__Search.search("where") {
          | Ok(_output) => ()
          | Error(_) => failwith("expected to find `where`")
          }
        | _ => failwith("OS not supported")
        }
      },
    )
    Async.it(
      "should return an error when the command is not found",
      async () => {
        switch await Connection__Command__Search.search("non-existent-command") {
        | Ok(_output) => failwith("expected to not find `non-existent-command`")
        | Error(_) => ()
        }
      },
    )
  })

  describe("findCommands", () => {
    Async.it(
      "should return the connection when a command is found",
      async () => {
        let commands = ["agda", "als"]
        switch await Connection.findCommands(commands) {
        | Ok(_) => ()
        | Error(_) => failwith("expected to find `agda` or `als`")
        }
      },
    )

    Async.it(
      "should return an error when the command is not found",
      async () => {
        let commands = ["non-existent-command"]
        switch await Connection.findCommands(commands) {
        | Ok(_) => failwith("expected to not find `non-existent-command`")
        | Error(_) => ()
        }
      },
    )
  })

  describe("make", () => {
    Async.it(
      "should return a connection and add it to the Memento when the command is found",
      async () => {
        // get the path of `agda` first
        let path = switch await Connection.findCommands(["agda"]) {
        | Ok(path) => path->Connection.Target.toURI->Connection__Target.URI.toString
        | Error(_) => failwith("expected to find `agda`")
        }

        // remove all paths in the config
        await Config.Connection.setAgdaPaths([])
        let paths = Config.Connection.getAgdaPaths()

        let memento = State__Memento.make(None)
        let commands = ["agda", "als"]
        switch await Connection.make(memento, paths, commands) {
        | Ok(_) => ()
        | Error(_) => failwith("expected to find `agda` or `als`")
        }

        Assert.deepEqual(Config.Connection.getAgdaPaths(), [path]->Array.map(Connection__URI.parse))

        let pathIsNowInConfig =
          Config.Connection.getAgdaPaths()->Util.Array.includes(path->Connection__URI.parse)
        Assert.ok(pathIsNowInConfig)

        switch await Connection.Target.getPicked(memento, Config.Connection.getAgdaPaths()) {
        | Error(_) => failwith("expected to find the picked connection")
        | Ok(picked) =>
          Assert.deepStrictEqual(
            picked->Connection.Target.toURI->Connection__Target.URI.toString,
            path,
          )
        }
      },
    )

    Async.it(
      "should return a connection and add it to the Memento when the command is found",
      async () => {
        // get the path of `agda` first
        let path = switch await Connection.findCommands(["agda"]) {
        | Ok(path) => path->Connection.Target.toURI
        | Error(_) => failwith("expected to find `agda`")
        }

        await Config.Connection.setAgdaPaths(["some/other/path"]->Array.map(Connection__URI.parse))
        let paths = Config.Connection.getAgdaPaths()

        let memento = State__Memento.make(None)
        let commands = ["agda", "als"]
        switch await Connection.make(memento, paths, commands) {
        | Ok(_) => ()
        | Error(_) => failwith("expected to find `agda` or `als`")
        }

        Assert.deepEqual(Config.Connection.getAgdaPaths(), [...paths, path])

        let pathIsNowInConfig = Config.Connection.getAgdaPaths()->Util.Array.includes(path)
        Assert.ok(pathIsNowInConfig)

        switch await Connection.Target.getPicked(memento, Config.Connection.getAgdaPaths()) {
        | Error(_) => failwith("expected to find the picked connection")
        | Ok(picked) => Assert.deepStrictEqual(picked->Connection.Target.toURI, path)
        }
      },
    )

    Async.it(
      "should do nothing when the command is already in the paths of the config",
      async () => {
        // get the path of `agda` first
        let path = switch await Connection.findCommands(["agda"]) {
        | Ok(path) => path->Connection.Target.toURI
        | Error(_) => failwith("expected to find `agda`")
        }

        await Config.Connection.setAgdaPaths([path, Connection__URI.parse("some/other/path")])
        let paths = Config.Connection.getAgdaPaths()

        let memento = State__Memento.make(None)
        let commands = ["agda", "als"]
        switch await Connection.make(memento, paths, commands) {
        | Ok(_) => ()
        | Error(_) => failwith("expected to find `agda` or `als`")
        }

        Assert.deepEqual(Config.Connection.getAgdaPaths(), paths)

        switch await Connection.Target.getPicked(memento, Config.Connection.getAgdaPaths()) {
        | Error(_) => failwith("expected to find the picked connection")
        | Ok(picked) => Assert.deepStrictEqual(picked->Connection.Target.toURI, path)
        }
      },
    )
  })

  // describe("State__Request.onCannotFindALSorAgdaError", () => {
  //   Async.it(
  //     "should download the latest version of ALS",
  //     async () => {
  //       switch await Connection.downloadLatestALS() {
  //       | Ok(_) => ()
  //       | Error(_) => failwith("expected to download the latest version of ALS")
  //       }
  //     },
  //   )
  // })
})
