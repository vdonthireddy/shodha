# Shodha: The Layman's Guide 🐣

Welcome to **Shodha**! This guide is written in plain, friendly language to explain what Shodha is, how it works behind the scenes, and how to get the most out of it—without any confusing tech jargon.

---

## 🧐 What is Shodha?

The name **Shodha** comes from Sanskrit and Telugu (**శోధ / शोध**), meaning **Search, Quest, Inquiry, and Discovery**. 

Think of Shodha as a friendly little companion that lives on your Mac desktop. Unlike web chatbots that stay trapped inside a browser tab or an app window you constantly have to minimize and maximize, Shodha **floats gently over your screen**.

Whenever you have a question, need an explanation, or want a quick reminder, you just click Shodha's avatar, type your thought, and you get an answer instantly.

---

## 🧩 How Does Shodha Work? (The Three-Part Anatomy)

You can understand Shodha through three simple parts:

```
    [ The Face ]                  [ The Brain ]                  [ The Hands ]
    Floating Avatar        ===>   Local AI (Ollama)      ===>    Tool Scheduler (MCP)
  (Floats on screen,              (Thinks, answers,              (Sets timers, rings
   blinks, and talks)              and keeps data private)        Mac reminders)
```

### 1. The Face (The Floating Avatar)
- **It floats everywhere:** Whether you are browsing the web, editing documents, or watching a video, Shodha stays on top. You can drag it to any corner of your screen that feels comfortable.
- **It has personality:** Shodha blinks, glows, and moves its mouth when it talks out loud.
- **You can dress it up:** You can choose the cute robot mascot or upload your own favorite picture as Shodha's face!

### 2. The Brain (Your Private Local AI)
- **Private and runs on your Mac:** Shodha connects to **Ollama**, an AI engine that runs directly inside your computer.
- **No creepy tracking:** Because the AI runs locally on your own machine, your questions, personal reminders, and notes are never sent to external cloud servers or used to train public models.

### 3. The Hands (The Action Worker / MCP)
- Have you ever told an AI: *"Remind me to drink water in 10 minutes"*, and it replied *"Sure! I'll remind you"*, but then nothing happened?
- Shodha has **hands** using a system called **MCP (Model Context Protocol)**. When you ask Shodha for a reminder, it doesn't just pretend—it actually writes down a timer on your computer. When the time arrives, a macOS banner notification pops up with sound!

---

## 🚀 How to Use Shodha in Your Day

### 1. Everyday Chat & Brainstorming
- Click the avatar to open the chat window.
- Type any question, such as:
  - *"Explain quantum computing like I'm 10 years old."*
  - *"Draft a friendly email asking my team for feedback."*
  - *"What is the difference between a latte and a cappuccino?"*
- Hit **Enter**. Shodha will write out the answer.

### 2. Listening with "Say It"
- If you don't feel like reading a wall of text, click the **"🔊 Say It"** button at the bottom of the chat box.
- Shodha will read the answer out loud using speech synthesis with animated mouth movements!
- If you need it to be quiet, just click **"⏹ Stop"**.

### 3. Setting Quick Reminders
- You can tell Shodha:
  - *"Remind me to submit my report in 20 minutes"*
  - *"Remind me to call Mom at 6:00 PM"*
  - *"Remind me to stretch every 30 minutes"*
- Shodha will confirm that the reminder is set. At the exact moment, your Mac will ring a bell and show a notification banner with your reminder text and Shodha's face.

### 4. Customizing Shodha's Look and Voice
- Click the gear icon (`⚙️`) in the header.
- **Change Avatar:** Pick the classic mascot or upload a picture of your pet, cartoon character, or favorite icon.
- **Change Voice:** Pick between Cute, Normal, Deep, or Chipmunk pitch, and adjust how fast or slow it talks.

---

## ❓ Frequently Asked Questions (FAQ)

#### Q: How do I close the chat box?
**A:** Just click anywhere outside the box on your desktop or another window! Shodha will automatically tuck the chat box away while keeping the avatar ready on screen.

#### Q: How do I quit the app completely?
**A:** Right-click the avatar and click **Quit Shodha**, or click the icon in your Mac's top Menu Bar and click **Quit**.

#### Q: Does Shodha work offline without internet?
**A:** Yes! Because Shodha uses local Ollama models on your Mac, it can answer questions, talk, and set reminders even when you are on an airplane or without Wi-Fi.

#### Q: Where are my reminders and settings saved?
**A:** Everything is safely stored in a folder on your Mac at:
`~/Library/Application Support/Shodha/`
