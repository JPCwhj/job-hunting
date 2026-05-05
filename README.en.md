# job-hunt · Resume Radar - Job Search Assistant Skill

[中文](README.md)

Screenshot any job listing from any hiring platform. AI parses the JD, matches it against your resume, generates tailored application materials, and ranks all positions by match score into a shortlist.

> **What it is**: A productivity tool, not an auto-apply bot. You decide when to hit "Apply".

---

## What It Does

1. **Resume quality check**: Upload your resume and AI diagnoses each section using industry-standard criteria (Situation + Action + Result), highlights weak spots, and suggests improvements. You can revise and re-upload, or skip and continue.
2. **JD parsing**: Upload screenshots of job listing pages from any major hiring platform. AI extracts structured data — title, salary, requirements, company size, etc.
3. **Match analysis**: Aligns each JD with your resume using STAR framework, outputting scores across 4 dimensions: Hard Skills / Experience Depth / Domain Fit / Soft Skills.
4. **Tailored materials**: Generates a customized resume + opening message + change log for each position.
5. **Shortlist output**: All positions ranked by match score, highest first.

---

## Who It's For

**Best fit**
- Job seekers applying with a text-based resume: product, operations, marketing, engineering, management, etc.
- Anyone applying to multiple positions who needs to tailor their resume for each JD
- Anyone who wants a quick read on how well they match a specific role

**Limited benefit**
- Roles where portfolio, design work, or visual output is the primary signal (UI/UX, graphic design, photography, architecture, etc.) — the competitive edge is in the work itself, not the resume text

---

## Install or Update

```bash
npx skills add JPCwhj/job-hunting -g
```

---

## Usage

**Option 1**: Launch any skill-compatible agent tool and run the corresponding command:
- Claude Code: `/job-hunt`
- Codex: `$job-hunt`

**Option 2**: In the chat window of a local AI agent tool like OpenClaw, send:

```
/job-hunt
```

**Workflow**:
1. Provide your resume (upload file, give a path, or paste text directly)
2. AI evaluates resume quality section by section — revise and re-upload, or continue as-is
3. Upload job listing screenshots (multiple at once, or in batches)
4. After confirming screenshots, analysis and tailoring run automatically — no extra trigger needed
5. Review shortlist, fill in placeholders, apply manually

**Re-run with a new resume**: Run `/job-hunt` again and it will prompt you to send your updated resume. Send it directly to replace the cached version — no need to clean first.

### Subcommands

| Command | Description |
|---|---|
| `/job-hunt` | Full flow (import → analyze → tailor → shortlist) |
| `/job-hunt fetch` | Import screenshots only (parse JDs into jd-pool) |
| `/job-hunt analyze` | Run match analysis on existing jd-pool |
| `/job-hunt tailor` | Sort + generate tailored materials |
| `/job-hunt status` | Check current run progress |
| `/job-hunt clean` | Clear all cache and output |

---

## Prerequisites

- **Your AI model must support vision (image recognition)**
- [Claude Code](https://github.com/anthropics/claude-code) installed, or any agent that supports the Skill spec (e.g. Codex, OpenClaw)
- If your resume is a Word document, upload it as `.docx` and install [docx skill](https://skills.sh/anthropics/skills/docx) first
- Any hiring platform — just screenshot the job detail page

---

## Output Structure

```
<current directory>/
└── jobHuntSkillData/
    ├── .work/
    │   ├── resume.md             ← your resume (auto-saved)
    │   └── jd-pool/              ← parsed JD cache
    └── output/
        └── 2026-05-02-1430/
            ├── shortlist.md      ← final ranked results
            ├── state.json        ← checkpoint state
            └── tailored/
                └── <company-title>/
                    ├── resume.md     ← tailored resume
                    ├── opener.md     ← opening message
                    └── changelog.md  ← what AI changed (transparency log)
```

---

## Design Boundaries

- **Works with all major hiring platforms**: any screenshot containing company name, job title, and JD is sufficient
- **No auto-apply**: eliminates account ban risk
- **No plugins or extensions required**: you screenshot, AI parses — no browser extensions or MCP tools needed
- **Ethical resume rewriting**: only rewrites wording and structure; never fabricates experience; invented numbers must use `[fill in: xxx]` placeholders; every change is logged in `changelog.md` for your review

---

## Data & Privacy

- **All files stay on your machine**: resume, JDs, and tailored materials are written to your local `jobHuntSkillData/` directory — nothing is auto-uploaded or synced anywhere
- **Data only passes through the Claude you're already using**: the skill connects to no third-party servers; the data path is identical to using Claude directly
- **The skill itself is plain text**: no network request code — inspect the source anytime at `~/.claude/skills/`
