# Marketing Copy — Proposed Rewrites (second pass)

Drafted from `app/views/static_pages/` as of 2026-10-27. Nothing in the views has been changed.

## What changed from the first pass

**Claims checked against the code.** Only a few tools actually connect:
- Saved recipes go into the meal plan.
- The meal plan generates the grocery list.
- The restock list appears as a second tab on the grocery list, sorted by store.
- Plan your week walks through the calendar, meals, restock list, groceries, chores and to-dos in order.

Chores, to-dos and the calendar otherwise stand on their own. None of the proposals below claim more than that.

**The pacing now follows your own lines, not mine.** The best guide to your marketing voice turned out to be copy you've already written on the grocery list, recipe and calendar pages, more than the Substack essays. Here's what those lines do:
- They use full sentences that explain why something helps, joined with *so*, *because* and *while*.
- They describe an everyday frustration in concrete terms, like "walking back and forth from aisle to aisle" or "endlessly digging through Pinterest."
- They name the problem plainly with "Stop…", "No more…" and "Say goodbye to…".
- They talk about the **mental** side of running a home: "Let us do the mental work" and "without the mental overwhelm."
- Short sentences are rare, and they come one at a time, never in stacked pairs.

**What I dropped:**
- "Every ___ in one ___" constructions
- Back-to-back two-sentence quips
- Clever reversals ("The grocery list takes none")
- "Imagine…" headlines
- Jokes tacked onto the end of a feature description

**Keep** means the current line already sounds like you. Lines you wrote yourself are mostly kept, with only typo fixes.

---

## Home (`home.html.erb`)

| Element | Current | Proposed                                                                                                                                                                                                                                                                                     |
|---|---|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| H1 | Run your household from one place | **Keep**                                                                                                                                                                                                                                                                                     |
| Hero paragraph | Plan meals and your week, generate the grocery list automatically, keep every recipe you love in one bank, share out the chores and to-dos, and see the whole family's calendar in one view — no more sticky notes on the fridge. | Most households are run from sticky notes on the fridge, a few group texts, and whatever someone happens to remember. HomemakersHaven brings your meal plan, grocery list, recipes, chores, to-dos, and family calendar together so you can spend less of your week keeping track of it all. |
| Section H2 | Everything you need, nothing you don't | **Keep**                                                                                                                                                                                                                                                                                     |
| Section paragraph | Tools that work together, so planning dinner, shopping for it, and getting the dishes done doesn't take five different apps. | Your saved recipes can be added straight to the meal plan, and the meal plan builds your grocery list for you.                                                                                                                                                                               |
| Card: Meal planning | Plan breakfast, lunch, and dinner for the week and see the nutrition and cost per serving as you go. | Plan breakfast, lunch, and dinner for the week, with nutrition and cost per serving updating as you go.                                                                                                                                                                                      |
| Card: Grocery lists | Your shopping list builds itself from whatever's on the meal plan — no more forgotten ingredients. | Your grocery list is generated directly from the meal plan, so you're not realizing halfway through making dinner that you forgot an ingredient.                                                                                                                                             |
| Card: Recipe bank | Write a recipe from scratch, import it from a URL, upload a document, or snap a photo of a cookbook page. | Write a recipe from scratch, import it from a website, upload a document, or take a photo of a cookbook page.                                                                                                                                                                                |
| Card: Plan your week | A guided walk through the week ahead — meals, to-dos, chores and the grocery list — in one sitting. | Plan your whole week in minutes with our guided tool.                                                                                                                                                                                                                                        |
| Card: To-do lists | A shared board for household tasks, with a weekly time budget so you don't take on too much. | A shared board for household tasks, with a weekly time budget that keeps you from taking on more than you can handle.                                                                                                                                                                        |
| Card: Chore chart | Hand out chores to everyone in the house, set how often they repeat, and tick them off the week. | Categorize and assign chores to everyone in the house, set how often each one repeats, and check them off as the week goes on.                                                                                                                                                               |
| Card: Restock list | Keep track of the household staples, mark what's running low, and shop it store by store. | Keep track of the household staples, mark what's running low, and shop for them store by store.                                                                                                                                                                                              |
| Card: Shared calendar | Sync every family calendar into one view so nobody double-books the minivan. | Sync each family member's calendar together so nothing gets missed.                                                                                                                                                                                                                          |
| Pricing H2 | One plan. Every feature. No per-person fees. | **Keep**                                                                                                                                                                                                                                                                                     |
| Pricing paragraph | Every household plan includes every feature — meal planner, grocery lists, recipe bank, to-dos, chores, restock list, and shared calendar — for everyone you invite. | Every household plan includes the meal planner, grocery lists, recipe bank, to-dos, chores, restock list, and shared calendar for everyone you invite, so the price stays the same whether there are two of you or eight.                                                                    |
| Bottom CTA | Ready to get the whole household organized? / (subs) | **Keep**                                                                                                                                                                                                                                                                                     |

---

## Pricing (`pricing.html.erb`)

| Element | Current | Proposed |
|---|---|---|
| H1 | Simple, honest pricing | **Keep** |
| Hero paragraph | One plan for the whole household. Every feature included, however many people you invite. Try it free for 30 days — no credit card needed to start. | One plan covers your whole household, and every feature is included no matter how many people you invite. Your first 30 days are free, and you won't need a credit card to start. |
| Monthly / Annual cards | (subtitles and bullets) | **Keep** |
| FAQ: Launch list | Everyone who joins the list before launch gets their first three months free instead of one — just sign up with the same email address. | Everyone who joins the list before launch gets their first three months free instead of one. When we open, just sign up using the same email address you joined the list with. |
| Other FAQs | (free trial, whole household, switching, cancelling) | **Keep** |
| CTAs | (both) | **Keep** |

---

## Plan Your Week (`plan_week.html.erb`)

| Element | Current | Proposed |
|---|---|---|
| H1 | Sit down once, and the whole week is planned | **Keep** |
| Subheadline | Plan your week walks you through everything the household needs for the days ahead — the calendar, meals, the restock list, groceries, chores and to-dos — one step at a time. | Plan your week walks you through everything your household needs for the days ahead, one step at a time. It starts with your calendar so you know which nights are busy, then moves through meals, the restock list, groceries, chores, and to-dos. |
| Start with what's already on | See the week's appointments and practices first, so you plan meals and chores around the busy nights. | Because you see the week's appointments and practices first, you can plan meals and chores around the busy nights instead of finding out about them on Wednesday. |
| One step at a time | Plan meals, top up the restock list, build the grocery list, hand out chores and pick this week's to-dos — each step picks up where the last left off. | Plan meals, top up the restock list, build the grocery list, hand out chores, and pick this week's to-dos, with each step picking up where the last one left off. |
| Pick up where you left off | Get interrupted halfway? Come back later and you're right back on the step you were on. Skip any step your household doesn't use. | **Keep** |
| Fit the to-dos to your time | Set aside how much time you have for to-dos this week, and see straight away when you've planned more than fits. | Set aside how much time you actually have for to-dos this week, and you'll see right away when you've planned more than will fit. |
| Plan ahead | Plan this week or get a head start on next week — each one keeps track of what's done. | **Keep** |
| Print the plan | Print the week's meals, groceries, chores and to-dos for the fridge in one PDF. | Print the week's meals, groceries, chores, and to-dos as a single PDF to hang on the fridge. |
| CTA | Twenty minutes on Sunday. A calmer week. / Plan the whole household's week in one sitting. | Spend twenty minutes on Sunday and have a calmer week. / Plan the whole household's week in one sitting. |

---

## Meal Planning (`meal_planning.html.erb`)

| Element | Current | Proposed                                                                                                                                                                         |
|---|---|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| H1 | Plan the whole week in minutes | **Keep**                                                                                                                                                                         |
| Subheadline | Drop recipes into a weekly grid for breakfast, lunch, and dinner, plus snacks and desserts. See servings, calories, and cost per serving update as you build the plan. | Drop recipes from your recipe bank into a weekly grid for breakfast, lunch, dinner, snacks, and desserts. Servings, calories, and cost per serving update as you build the plan. |
| Pull straight from your recipe bank | Add any saved recipe to a day and meal slot — no retyping ingredients or instructions. | Any recipe you've saved can be added to a day and meal with its ingredients and instructions already included, so there's no retyping.                                           |
| See the real cost | Every meal shows calories, macros, and an estimated cost per serving, so you know what the week will actually cost. | Every meal shows calories, macros, and an estimated cost per serving, so you know what the week will actually cost before you get to the store.                                  |
| Flip between weeks | Move forward or back a week to plan ahead or review what you already cooked. | **Keep**                                                                                                                                                                         |
| CTA | Plan next week's meals in one sitting / Then let HomemakersHaven build the grocery list for you. | **Keep**                                                                                                                                                                         |

---

## Grocery Lists (`grocery_lists.html.erb`)

| Element | Current | Proposed |
|---|---|---|
| H1 | Your shopping list, built for you | **Keep** |
| Subheadline | HomemakersHaven reads whatever's on the meal plan and generates a grocery list automatically — grouped by category, with quantities combined across every recipe that needs them. | **Keep** |
| Auto-Generated List | Your grocery list will auto-generate from your meal plan, combining quantities and serving sizes across recipes. Say goodbye to realizing you forgot a critical ingredient when you are making dinner | Say goodbye to realizing you forgot a critical ingredient when you're in the middle of making dinner. Your grocery list is generated from your meal plan, combining quantities and serving sizes across every recipe. |
| Grouped by category and store | Your grocery list is automatically organized by category. No more walking back and forth from aisle to aisle because you forgot an item on the other side of the store | Your grocery list is automatically organized by category. No more walking back and forth from aisle to aisle because you forgot an item on the other side of the store. |
| Track what's left to buy | Check items off as you shop and see an estimated subtotal for the whole trip. | **Keep** |
| CTA headline | Stop forgeting critical ingredients or buying the wrong amount at the grocery store | Stop forgetting critical ingredients or buying the wrong amount at the grocery store |
| CTA sub | Let us do the mental work. | **Keep** |

---

## Recipe Bank (`recipes.html.erb`)

| Element | Current | Proposed                                                                                                                                                                                                    |
|---|---|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| H1 | Every recipe you love, in one bank | Stop digging for the recipe you saved months ago                                                                                                                                                            |
| Subheadline | Keep all of your family's favorite recipes in one place, organized into collections however you like. With nutrition facts and estimated costs built into every recipe, you can stay on track with your nutrition and budget goals—without the mental overwhelm. Stop reinventing the wheel every week or endlessly digging through Pinterest trying to find that recipe you saved months ago. | Keep all of your family's favorite recipes in one place, organized into collections however you like. No more reinventing the wheel every week or scrolling back through Pinterest trying to find it again. |
| "Four ways" paragraph | Whichever way a recipe reaches you, it ends up in the same organized bank. | Quickly save any recipe, whichever way it reaches you.                                                                                                                                                      |
| Four card descriptions *(commented out)* | (as written in the view) | **Keep** — the originals are fine if you uncomment them                                                                                                                                                     |
| CTA | Bring your recipes over in minutes / However your recipes are scattered today, they'll end up in your own searchable and customizable bank. | **Keep**                                                                                                                                                                                                    |

---

## To-Do Lists (`todos.html.erb`)

| Element | Current | Proposed                                                                                                                                                                             |
|---|---|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| H1 | One list for everything the household needs to get done | **Keep**                                                                                                                                                                             |
| Subheadline | Track chores, errands, and appointments on a shared board with priorities — and see them laid out on a timeline so you know what's coming up this week. | No more forgetting to call and set up that appointment. See everything you need to do all laid out so you know what's coming up this week.                                           |
| Detail title: "Organize by status" | Organize by status | Pick this week's to-dos |
| Organize by status | Move tasks from To-Do into To-Do This Week, then Completed, as the household works through them. | Focus on the most important things first. Pick and choose the key things you want to accomplish this week and stop the to-do overwhelm.                                              |
| Set a priority | Mark tasks Low, Medium, High, or Urgent so it's obvious what needs attention first. | **Keep**                                                                                                                                                                             |
| See the week at a glance | Set aside time for to-dos each week, and a chart lays out what's planned against it — so you can tell when you've taken on too much. | Set aside a certain amount of time for to-dos each week, and a chart lays out everything you've planned against it so you can tell when you've taken on more than you have time for. |
| CTA | Get the whole household on the same to-do list / Chores, errands, and appointments — all in one shared board. | Get the whole household on the same to-do list / Errands, appointments, and household projects on one shared weekly list.                                                            |
| Screenshot alt text | A to-do board with To Do, In Progress, and Done columns and a weekly timeline in HomemakersHaven | This week's to-dos alongside the household's to-do list and a weekly timeline in HomemakersHaven |
| Meta description | A shared to-do board for the household, with priorities, tags and a weekly plan that fits the time you have. | A shared to-do list for the household, where you pick what to focus on each week and see whether it fits the time you have. |

---

## Chore Chart (`chores.html.erb`)

| Element | Current | Proposed |
|---|---|---|
| H1 | Everyone knows whose turn it is | **Keep** |
| Subheadline | Put every household chore on one chart, give each one to someone, and set how often it comes around. Weekly chores land on their day by themselves, and the less frequent ones show up when they're due. | Put every household chore on one chart, assign each one to someone, and set how often it comes around. Weekly chores show up on their day automatically, and the less frequent ones show up when they're due. No more reminding everyone whose turn it is. |
| Start from a template | Pick from ready-made lists of chores for the kitchen, bathrooms, laundry, yard and more, then make them your own. | Start from ready-made lists of chores for the kitchen, bathrooms, laundry, yard, and more, then adjust them to fit your home. |
| Daily to once a year | Set how often each chore repeats. Weekly ones land on the same day every week; monthly and yearly ones show up under Due soon when it's time. | Set how often each chore repeats. Weekly chores land on the same day every week, while monthly and yearly ones show up under Due soon when it's time. |
| Hand them out | Give each chore to someone in the household — color-coded, so everyone can spot their own at a glance. | Assign each chore to someone in the household. Everyone is color-coded so they can spot their own chores at a glance. |
| Break it into steps | Add a checklist to a bigger chore, so "clean the bathroom" means the same thing to everyone. | Add a checklist to bigger chores so that "clean the bathroom" means the same thing to everyone in the house. |
| Drag to reschedule | Busy Tuesday? Drag a chore to another day — just this week, or from now on. | **Keep** |
| Kids can join in | Give kids their own login to see and tick off their chores, without being able to change the rest of the household's plans. | Kids can have their own login to see and check off their chores without being able to change the rest of the household's plans. |
| CTA | Stop being the one who remembers every chore / Share the load — and the chart — with the whole household. | **Keep** |

---

## Restock List (`restock.html.erb`)

| Element | Current | Proposed |
|---|---|---|
| H1 | Never run out of toilet paper again | **Keep** |
| Subheadline | Keep a checklist of everything the house runs on — paper towels, dish soap, coffee, dog food — and mark what's running low. It becomes a shopping list, sorted by the store you buy it from. | Keep a checklist of the things your house runs on, like paper towels, dish soap, coffee, and dog food, and mark what's running low. Those items become a shopping list sorted by the store you buy them from, right next to your grocery list. |
| Detail grid | (all three) | **Keep** |
| CTA headline | Know what you're out of before you're out of it | **Keep** |
| CTA sub | Keep the whole household's staples stocked. | Keep the household stocked without having to remember what's running low. |

---

## Shared Calendar (`calendar.html.erb`)

| Element | Current | Proposed |
|---|---|---|
| H1 | The whole family's schedule, in one view | No more calendar surprises |
| Subheadline | Sync all of you calendars from Google, Outlook, and Microsoft 365 to create a household calendar. View your week ahead of time to strategizes and prepare for busy days. No more calender surprises. | Sync all of your calendars from Google, Outlook, and Microsoft 365 to create one household calendar. View your week ahead of time so you can plan and prepare for the busy days. |
| Detail grid | (all three) | **Keep** |
| CTA | Stop missing what's on everyone else's calendar / Sync every family calendar into one shared view. | Stop missing what's on everyone else's calendar / Sync your family's calendars together and see everyone's week at once. |

---

## Shared Components

| Element | Current | Proposed |
|---|---|---|
| Footer tagline (`_footer`) | Everything your household runs on, in one place. | Meal planning, groceries, chores, and the family calendar for your whole household. |
| Launch list note (`_launch_list_form`) | Join the list and we'll email you when we launch — your first three months are free. No spam; unsubscribe anytime. | **Keep** |

---

## Other things to check

- **"Grouped by category and store" (Grocery Lists).** The description only talks about category. The store-by-store grouping I found in the code belongs to the restock tab. If the grocery tab isn't split by store, the title should just say category.
- **Leftover references to the old to-do board.** The to-do page now describes a weekly list, so these other spots still need updating:
  - The "Organize by status" detail title. There's a new row for it in the To-Dos table.
  - The screenshot alt text, which still describes To Do / In Progress / Done columns.
  - The meta description.
  - The Home card ("A shared board for household tasks…") still says "board". I left your edited row alone, but "a shared weekly list" would match.
  - The Plan your week page's "pick this week's to-dos" already fits the new model.
- **The Pricing page's Monthly feature list** still leaves out chores, the restock list and Plan your week.
