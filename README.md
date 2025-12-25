# Service Composer

This project was originally conceived many years ago (in the pre-LLM era) when I had the task of translating video subtitles using AWS. This translation task can be broken into multiple steps: strip audio from the original video, upload audio to the cloud, transcribe the audio, translate into multiple languages, download translations, generate new video subtitles. The AWS platform provided transcription and translation services, but to connect the two required S3 as an intermediary. Using the AWS SDK I had the choice of a number of languages with which to glue it all together, but what I really would have preferred was an executable recipe that *described* how to glue all the services together. I also wanted the freedom to pick and choose between service providers: e.g. a recipe that could specify AWS for transcription and Azure for translation or whichever was best (or cheapest). Finally, I wanted the composing service to just ask me when it needed more information. Perhaps the service provider has a quality attribute I didn't know about. If so, it should just ask me if I care enough to specify the quality.

Service composer is just a dispatching service. It receives a description of a task (a recipe) and dispatches each step of the task to the relevant service provider. A recipe is a linear or (more often) hierachical specification of the steps required to resolve the task. Each step describes a service provider, a local or remote service with a well-defined API. Each step may (or may not) specify the required and optional attributes needed to resolve the step. So what happens if required attributes are not specified? The service provider just asks for them. The way this works is that each step acts like a curried function i.e. each service provider has a resolver function that takes just one argument at a time and is partially applied. Ultimately, the resolver function for a step can have as many arguments as it needs but the implementation handles just one argument at a time. If a required argument is not supplied, the service provider can just ask for it. It does so by specifying the argument name and expected type and this information is conveyed via the service dispatcher (the overall composer) to whatever is being used to interact with the user.

Although the original concept was about glueing together cloud services, it has some relevance to the LLM era as well. To put it another way, the *user* may be an LLM. The usual procedure for a tool-using agent is to call a single service at a time, passing all of the required arguments to the underlying agent runner as a tool-call. For a complicated task, the agent may have to dispatch a series of tool calls and then assemble an answer from the results. An alternative is for the agent to call a single service dispatcher and pass it a recipe. The dispatcher then transparently kicks off multiple tool calls that run across multiple service providers. In the first case, the agent was in charge of dispatch and assembly. In the second, a service composer. However, only the service composer could produce a deterministic result.

## Examples

A service composer can't do anything at all without some services to compose. The examples folder contains some very simple service provider examples and a web service and web client that interact with them. Using two command line terminals (one for the dispatcher and one for the web service), here's how you run them:

```sh
// start the web client
cd examples/web_client
gleam run -m lustre/dev start

// in the second terminal, start the web service
// the web service will start the service composer dispatcher
cd examples/web
gleam run    // ignore the warnings

// now start a browser and navigate to http://localhost:1234/
// this will talk to the web service at http://127.0.0.1:3000
```
