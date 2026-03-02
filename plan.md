read lyrics.md and wikipedia.md for context first, then proceed

I want you to scaffold a CLI coding agent in ~/powerglide, called "powerglide", and hosted at the remote - github.com/bkataru/powerglide (use gh cli to create/manage this repo)

named after the catchy rae sremmund song - https://u92slc.com/life/watch-how-rae-sremmurd-created-powerglide/ , https://en.wikipedia.org/wiki/Powerglide_(song) that itself describes the powerglide transmission in lamborghinis that is used for drag racing, the choice of naming is a reference/alludes to the "driving a fast supercar" nature of cli coding agents such as claude code, codex, gemini CLI, opencode, forgecode, kilo code, cursor CLI, etc. what's common among all of them is that they are each a particular type of agent harness - designed for extreme coding workflows in the terminal by leveraging multi agent setups that fail-over gracefully, don't crash, and keep themselves going while also utilizing multiple models, tools, prompts, skills, data sources (memory/context), state machines, and other bells and whistles to keep them going even if a tool call messes up and puts the agent harness into an erroneous state

cli coding agents are like a drug because it literally feels like you have the wheel, and the agent(s) are your copilot/autopilot, like a semi-autonomous driving car, where it is usually in autopilot but the user can take the wheel and is consulted with human in the loop decisions at the right times, and you're capable of building out entire businesses and large scale projects and codebases if one learns to drive them well 

it is inspired by and uses as references:
    - [opencode](https://github.com/anomalyco/opencode) + [oh my opencode](https://github.com/code-yeongyu/oh-my-opencode)
    - [forge code](https://forgecode.dev)
    - [aichat](https://github.com/sigoden/aichat)
    - [loki](https://github.com/Dark-Alex-17/loki)
    - [goose](https://github.com/block/goose)
    - [plandex](https://github.com/plandex-ai/plandex)
    - [oh-my-pi](https://github.com/can1357/oh-my-pi)
    - [pi-mono](https://github.com/badlogic/pi-mono)
    - [crush](https://github.com/charmbracelet/crush)
    - [ralph](https://github.com/snarktank/ralph)
    - [The Ralph Playbook](https://github.com/ghuntley/how-to-ralph-wiggum)
    - [The Ralph Playbook (another version)](https://github.com/ClaytonFarr/ralph-playbook)
    - [mem0 - memory layer for AI agents](https://github.com/mem0ai/mem0)
    
oh-my-pi and forge code are the primary/main inspirations (in that order), but others are important as well in terms of learning from their featureset and methodologies
    
obtain a repomix xml file of each of the codebases of the projects listed above, so you can study them when designing and making powerglide, to understand what makes each project special and how they can contribute to powerlide's overall vision (run repomix --help or npx repomix --help for more context)

you will be building powerglide in zig 0.15.2, which is installed and available in path (run which zig and zig --version to locate it), there are breaking changes in zig 0.15 pertaining to the new Reader/Writer Io interface, so you will have to gather some context on these + at times keep referring to the zig stdlib library source code (can be obtained by finding out where the zig binary is using which zig and then navigating backwards to the lib folder)

powerglide is/will be the main CLI coding agent tool that is wielded by Barvis, Baala's Jarvis, my OpenClaw agent

- https://www.moltbook.com/u/barvis_da_jarvis : barvis on moltbook
- https://github.com/bkataru/zeptoclaw : zeptoclaw, the AI agent computer/OpenClaw like framework that powers Barvis, custom built for Barvis in Zig, read its README and docs to understand the kind of philosophy that goes into Barvis' tooling, read and understand its codebase to fully grok the underlying infrastructure powering barvis
- https://github.com/bkataru/barvis : private gh repo containing barvis' memory and state files that you can access using the gh cli to understand who barvis is


powerglide must be capable of multi-agent orchestration, and deploying a swarm of SWE agents/workers and monitoring their progress reliably without unintentionally spawning rogue/runaway subagents (as is often possible in oh-my-opencode if a slightly less smart model is put in a very intense agent harness with a loaded session prompt, it's not a tight enough ralph loop in my opinion)

also, it should be possible to control the "velocity" of the ralph loop/state machine that powers each agent/subagent, i.e., that this should be a configureable parameter that can be configured by both humans and agents spawned by powerglide as well as external agents that are orchestrating/operating powerglide and its agents by calling it in the CLI, one of my biggest pain points with CLI coding harnesses, CLI agent harnesses, and agent harnesses in general that integrate with terminal as a tool or terminal as a capability for the agent, is that they are not able to read/obtain the exit code of each command in a reliable manner + they struggle with orchestrating multiple agents each capable of operating one ore more terminals (in a full CRUD like fashion) and reading the outputs from one ore more terminals, we need to build a resilient, self-healing, recoverable, fault tolerant, and intelligent agent harness with powerglide, that is capable enough to improve itself over a long period of time with long horizon coding agents powered by a powerful, capable model, but big (in size and cost in an abstract sense) model (orchestrator agents with low "velocities" i.e. session progress rate, where a session is defined as a conversation, a collection of user, agent responses one after another) orchestrating, delegating, and coordinating, multiple fast coding agents that are powered by weaker, less intelligent yet enthusiastic and fast responding models (a la steve yeggie's gastown)

here are some links for references you need to go through in detail and reading that you need to do

https://github.com/bkataru?tab=stars | Your Stars
https://github.com/msitarzewski/agency-agents/blob/main/testing/testing-reality-checker.md | agency-agents/testing/testing-reality-checker.md at main · msitarzewski/agency-agents
https://github.com/modiqo | Modiqo
https://github.com/modiqo/dex-releases | modiqo/dex-releases: Public release binaries for dex - Execution Context Engineering
https://github.com/snarktank/ralph | snarktank/ralph: Ralph is an autonomous AI agent loop that runs repeatedly until all PRD items are complete.
https://github.com/ghuntley/how-to-ralph-wiggum | ghuntley/how-to-ralph-wiggum: The Ralph Wiggum Technique—the AI development methodology that reduces software costs to less than a fast food worker's wage.
https://github.com/ClaytonFarr/ralph-playbook | ClaytonFarr/ralph-playbook: A comprehensive guide to running autonomous AI coding loops using Geoff Huntley's Ralph methodology. View as formatted guide below 👇
https://github.com/code-yeongyu/oh-my-opencode/issues/1948 | Heads up: opencode titlecase() crash when task() called without subagent_type (workaround inside) · Issue #1948 · code-yeongyu/oh-my-opencode
https://github.com/anomalyco/opencode | anomalyco/opencode: The open source coding agent.
https://github.com/Dark-Alex-17/loki | Dark-Alex-17/loki: An all-in-one, batteries included LLM CLI tool
https://github.com/bkataru?tab=repositories | Your Repositories
https://github.com/steveyegge/gastown | steveyegge/gastown: Gas Town - multi-agent workspace manager
https://relatedrepos.com/gh/steveyegge/beads | steveyegge/beads alternatives and similar packages
https://relatedrepos.com/gh/mem0ai/mem0 | mem0ai/mem0 alternatives and similar packages
https://relatedrepos.com/gh/humanlayer/12-factor-agents | 12-factor-agents alternatives and similar packages
https://github.com/humanlayer/12-factor-agents | humanlayer/12-factor-agents: What are the principles we can use to build LLM-powered software that is actually good enough to put in the hands of production customers?
https://relatedrepos.com/gh/jdx/mise | jdx/mise alternatives and similar packages
https://github.com/jdx/mise | jdx/mise: dev tools, env vars, task runner
https://github.com/steveyegge/beads | steveyegge/beads: Beads - A memory upgrade for your coding agent
https://relatedrepos.com/gh/Dicklesworthstone/beads_viewer | beads_viewer alternatives and similar packages
https://relatedrepos.com/gh/eyaltoledano/claude-task-master | claude-task-master alternatives and similar packages
https://relatedrepos.com/gh/Dicklesworthstone/mcp_agent_mail | mcp_agent_mail alternatives and similar packages
https://relatedrepos.com/gh/oraios/serena | oraios/serena alternatives and similar packages
https://relatedrepos.com/gh/obra/superpowers | obra/superpowers alternatives and similar packages
https://relatedrepos.com/gh/ruvnet/ruflo | ruvnet/ruflo alternatives and similar packages
https://relatedrepos.com/gh/tobi/qmd | tobi/qmd alternatives and similar packages

you will very likely need to write/rewrite/implement a lot of AI-specific functionalities from scratch (although I incline you to use my personal zig stack for this task - github.com/bkataru and filtering by repositories with zig as the language should give you the list of projects I maintain in Zig + AI land) in Zig, but for more general purpose needs and functionalities + foundational software infrastructure that any coding agent will needed, I'd urge you to go find/search for zig dependencies and things we can use with `zig fetch` and build.zig.zon, for things like a terminal UI, a sandboxing environment, a CLI library, and other things we can offload to external vendors/deps to lessen the amount of work we have to do

ensure proper README.md, proper docs files documenting the source code with maximal coverage and comprehensive context, and extensive unit, integration, and e2e tests that validate, and guard against regressions with maximal test/feature coverage

ensure a very detailed CLI interface with a comprehensive --help command that can guide both natural and artificial intelligences very effectively on the many different "arms" of capabilities that powerglide has and how to wield them with precision and power


run opencode --help and forge --help to view examples of  CLI interfaces and command/options/flags setups I really personally admire and use on a daily basis,

at some point, build powerglide enough that you can use it to finish up everything listed in this comprehensive plan here to completion using itself, i.e., the ultimate dogfooding rite of passage in the AI coding age in my opinion


create zine based SSG docs under website/ (https://zine-ssg.io/), host them and deploy them after building on gh-pages, take a look at how igllama, another project of mine, does this

actually, powerglide should be very similar in style, design, vibe with igllama and zeptoclaw actually, considering how much they also use and are built with my personal github.com/bkataru stack

git add, git commit, git push always with bkataru (baalateja.k@gmail.com) as the commit author, not cjags, since this is my project


---

for implementation and writing code/docs: delegate oh-my-opencode agents and SWE work crews/swarms (run npx oh-my-opencode --help to understand how to do this), sleep on their outputs, go to my gists (gist.github.com/bkataru) using the gh cli to find and read relevant SKILL.md files that can guide you on opencode and oh-my-opencode multiagent orchestration where you are but an orchestrator that delegates, waits, and steers subagents, conserving context/token usage for yourself with proper separation and delegation of concerns