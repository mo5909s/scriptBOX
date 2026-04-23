# -----------------------------------------------
#  newsUpdate.ps1 - Personalized News Summary
# -----------------------------------------------
param(
    # -- NewsAPI (newsapi.org) -------------------------------------------------
    [string]$NewsApiKey    = "de0b8f0783d64addb6e24016f1044078",
    # -- Hacker News Algolia (no key required) --------------------------------
    [switch]$DisableHackerNews,
    # -- TheMealDB (themealdb.com - completely free, no key needed) -----------
    # -- GitHub Copilot AI summaries ------------------------------------------
    [string]$GitHubToken   = "",
    # -- General settings -----------------------------------------------------
    [string[]]$Tags        = @("technology", "space", "AI", "gaming", "science", "OpenAI"),
    [int]$ArticlesPerTag   = 3,
    [ValidateSet("en","de","fr","es","it","pt","nl","no","sv","ru","zh")]
    [string]$Language      = "en",
    [switch]$TopHeadlines,
    [switch]$NoColor,
    [switch]$SaveToFile,
    [string]$OutputPath    = "",
    [switch]$OpenInBrowser,
    [switch]$BrowserOnly
)
function Write-Color {
    param([string]$Text, [ConsoleColor]$Color = [ConsoleColor]::White)
    if ($BrowserOnly) { return }
    if ($NoColor) { Write-Host $Text }
    else          { Write-Host $Text -ForegroundColor $Color }
}
function HtmlEnc { param([string]$s) return [System.Net.WebUtility]::HtmlEncode($s) }
# =============================================================================
# RECIPE API  (TheMealDB - free, no key required)
# Uses day-of-year to pick a letter (a-z) and a meal index deterministically
# so the recipe changes daily but is consistent throughout the day.
# =============================================================================
function Get-DailyRecipe {
    $doy    = (Get-Date).DayOfYear
    $idx    = $doy % 26
    $letter = [char]([int][char]'a' + $idx)

    $url = "https://www.themealdb.com/api/json/v1/1/search.php?f=$letter"
    try {
        $r = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
        if (-not $r.meals -or $r.meals.Count -eq 0) { return $null }

        $pick = $doy % $r.meals.Count
        $meal = $r.meals[$pick]

        $link = if ($meal.strSource)    { $meal.strSource }
                elseif ($meal.strYoutube) { $meal.strYoutube }
                else                    { $meal.strMealThumb }

        return @{
            label   = $meal.strMeal
            url     = $link
            thumb   = $meal.strMealThumb
            cuisine = $meal.strArea
            meal    = $meal.strCategory
            time    = ""
            calories= ""
        }
    }
    catch {
        Write-Color "  [!] TheMealDB recipe fetch failed: $_" DarkYellow
        return $null
    }
}
# =============================================================================
# NEWSAPI
# =============================================================================
function Get-NewsEverything {
    param([string]$Tag)
    $url = "https://newsapi.org/v2/everything?q=$([System.Uri]::EscapeDataString($Tag))&language=$Language&sortBy=publishedAt&pageSize=$ArticlesPerTag&apiKey=$NewsApiKey"
    try   { $r = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop; return $r.articles }
    catch { Write-Color "  [!] NewsAPI /v2/everything failed for '$Tag': $_" Red; return @() }
}
function Get-NewsTopHeadlines {
    param([string]$Tag)
    $url = "https://newsapi.org/v2/top-headlines?q=$([System.Uri]::EscapeDataString($Tag))&language=$Language&pageSize=$ArticlesPerTag&apiKey=$NewsApiKey"
    try   { $r = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop; return $r.articles }
    catch { Write-Color "  [!] NewsAPI /v2/top-headlines failed for '$Tag': $_" Red; return @() }
}
function Get-NewsForTag {
    param([string]$Tag)
    if ($TopHeadlines) { return Get-NewsTopHeadlines -Tag $Tag }
    return Get-NewsEverything -Tag $Tag
}
# =============================================================================
# HACKER NEWS  (hn.algolia.com/api/v1  - no key required)
# =============================================================================
function Get-HackerNewsForTag {
    param([string]$Tag)
    $url = "https://hn.algolia.com/api/v1/search?query=$([System.Uri]::EscapeDataString($Tag))&tags=story&hitsPerPage=$ArticlesPerTag"
    try {
        $r = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
        return $r.hits
    }
    catch { Write-Color "  [!] HN Algolia failed for '$Tag': $_" Red; return @() }
}
# =============================================================================
# GITHUB COPILOT AI SUMMARY
# =============================================================================
function Get-AiSummary {
    param([string]$Headlines)
    if ([string]::IsNullOrWhiteSpace($GitHubToken)) { return $null }
    $body = @{
        model    = "gpt-4o"
        messages = @(
            @{ role = "system"; content = "You are a concise news assistant. Summarize the following headlines in 2 sentences max. Be direct and factual." },
            @{ role = "user";   content = $Headlines }
        )
        max_tokens = 120
    } | ConvertTo-Json -Depth 5
    try {
        $result = Invoke-RestMethod -Uri "https://api.githubcopilot.com/chat/completions" -Method Post `
            -Headers @{ Authorization = "Bearer $GitHubToken"; "Content-Type" = "application/json"; "Editor-Version" = "vscode/1.95.0"; "Copilot-Integration-Id" = "vscode-chat" } `
            -Body $body -ErrorAction Stop
        return $result.choices[0].message.content.Trim()
    }
    catch { Write-Color "  [!] Copilot AI summary failed: $_" DarkYellow; return $null }
}
function Format-PublishedAt {
    param([string]$IsoDate)
    try   { return [datetime]::Parse($IsoDate).ToLocalTime().ToString("dd.MM.yyyy HH:mm") }
    catch { return $IsoDate }
}
# =============================================================================
# GUARD
# =============================================================================
if ($NewsApiKey -eq "YOUR_NEWSAPI_KEY") {
    Write-Color "[!] Set your NewsAPI key. Get one free: https://newsapi.org/register" Yellow
    exit 1
}
# =============================================================================
# FETCH RECIPE
# =============================================================================
$recipe = Get-DailyRecipe
# =============================================================================
# FETCH NEWS
# =============================================================================
$allData = [System.Collections.Generic.List[hashtable]]::new()
foreach ($tag in $Tags) {
    $articleList  = [System.Collections.Generic.List[hashtable]]::new()
    $headlineList = @()
    # -- NewsAPI articles --
    $newsItems = Get-NewsForTag -Tag $tag
    if ($newsItems) {
        foreach ($article in $newsItems) {
            $entry = @{
                time   = Format-PublishedAt $article.publishedAt
                source = if ($article.source.name) { $article.source.name } else { "Unknown" }
                title  = ($article.title -replace "\s+"," ").Trim()
                url    = $article.url
                desc   = (($article.description -replace "\s+"," ").Trim())
                badge  = "NewsAPI"
            }
            if ($entry.desc.Length -gt 160) { $entry.desc = $entry.desc.Substring(0,160) + "..." }
            $articleList.Add($entry)
            $headlineList += $entry.title
        }
    }
    # -- Hacker News articles --
    if (-not $DisableHackerNews) {
        $hnItems = Get-HackerNewsForTag -Tag $tag
        if ($hnItems) {
            foreach ($hit in $hnItems) {
                $hnUrl = if ($hit.url) { $hit.url } else { "https://news.ycombinator.com/item?id=$($hit.objectID)" }
                $entry = @{
                    time   = Format-PublishedAt $hit.created_at
                    source = "Hacker News"
                    title  = ($hit.title -replace "\s+"," ").Trim()
                    url    = $hnUrl
                    desc   = ""
                    badge  = "HN"
                }
                $articleList.Add($entry)
                $headlineList += $entry.title
            }
        }
    }
    $aiSummary = $null
    if (-not [string]::IsNullOrWhiteSpace($GitHubToken) -and $headlineList.Count -gt 0) {
        $aiSummary = Get-AiSummary -Headlines ($headlineList -join "`n")
    }
    $allData.Add(@{ tag = $tag; articles = $articleList; summary = $aiSummary })
}
# =============================================================================
# TERMINAL OUTPUT
# =============================================================================
$hnLabel       = if ($DisableHackerNews) { "off" } else { "on (hn.algolia.com)" }
$endpointLabel = if ($TopHeadlines) { "Top Headlines" } else { "Everything" }
$aiLabel       = if ($GitHubToken)  { "GitHub Copilot (gpt-4o)" } else { "off" }
$recipeLabel   = "on (TheMealDB - free)"
$timestamp     = (Get-Date).ToString("dddd, dd MMMM yyyy - HH:mm")
$outputLines = [System.Collections.Generic.List[string]]::new()
function Emit {
    param([string]$Line, [ConsoleColor]$Color = [ConsoleColor]::White)
    if ($SaveToFile) { [void]$outputLines.Add($Line) }
    Write-Color $Line $Color
}
Emit ""
Emit "============================================================" Cyan
Emit "   [NEWS]  YOUR MORNING NEWS BRIEFING" Cyan
Emit "   $timestamp" Cyan
Emit "   NewsAPI  : $endpointLabel  |  HN: $hnLabel" DarkGray
Emit "   Recipe   : $recipeLabel  |  AI: $aiLabel" DarkGray
Emit "============================================================" Cyan
# -- Daily Recipe block --
if ($recipe) {
    Emit ""
    Emit "=== TODAY'S RECIPE RECOMMENDATION ===" Green
    Emit "  $($recipe.label)" White
    Emit "  Cuisine: $($recipe.cuisine)  |  Category: $($recipe.meal)" DarkGray
    Emit "  $($recipe.url)" DarkCyan
    Emit "============================================================" Green
}
foreach ($block in $allData) {
    Emit ""
    Emit "--- #$($block.tag.ToUpper()) ---" Yellow
    if ($block.articles.Count -eq 0) { Emit "  No articles found." DarkGray; continue }
    foreach ($a in $block.articles) {
        $src = if ($a.badge -eq "HN") { "[HN] $($a.source)" } else { "[API] $($a.source)" }
        Emit ""
        Emit "  * $($a.title)" White
        Emit "    $src  |  $($a.time)" DarkGray
        if ($a.desc) { Emit "    $($a.desc)" Gray }
        Emit "    $($a.url)" DarkCyan
    }
    if ($block.summary) {
        Emit ""
        Emit "  [AI Summary]" Magenta
        Emit "  $($block.summary)" Magenta
    }
    Emit ""
    Emit "------------------------------------------------------------" DarkGray
}
Emit ""
Emit "  Done. Tags: $($Tags -join ', ')" DarkGray
Emit ""
if ($SaveToFile) {
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = Join-Path $PSScriptRoot ("news_" + (Get-Date).ToString("yyyy-MM-dd_HHmm") + ".txt")
    }
    $outputLines | Set-Content -Path $OutputPath -Encoding UTF8
    Write-Color "  Saved to: $OutputPath" DarkGreen
}
# =============================================================================
# BROWSER HTML OUTPUT
# =============================================================================
if ($OpenInBrowser -or $BrowserOnly) {
    $recipeHtml = ""
    if ($recipe) {
        $rl  = HtmlEnc $recipe.label
        $ru  = $recipe.url
        $rc  = HtmlEnc $recipe.cuisine
        $rm  = HtmlEnc $recipe.meal
        $img = if ($recipe.thumb) { "<img src=`"$($recipe.thumb)`" alt=`"$rl`">" } else { "" }
        $recipeHtml = "<section class=`"recipe`"><h2>Today's Recipe</h2><article>$img<a href=`"$ru`" target=`"_blank`">$rl</a><div class=`"meta`">$rc &nbsp;|&nbsp; $rm</div></article></section>"
    }
    $sections = [System.Text.StringBuilder]::new()
    foreach ($block in $allData) {
        [void]$sections.Append("<section>")
        [void]$sections.Append("<h2>#$(HtmlEnc $block.tag.ToUpper())</h2>")
        if ($block.articles.Count -eq 0) {
            [void]$sections.Append("<p class='none'>No articles found.</p>")
        } else {
            foreach ($a in $block.articles) {
                $badgeCls  = if ($a.badge -eq "HN") { "hn" } else { "api" }
                $badgeTxt  = $a.badge
                $safeTitle  = HtmlEnc $a.title
                $safeSource = HtmlEnc $a.source
                $safeDesc   = HtmlEnc $a.desc
                $safeUrl    = $a.url
                [void]$sections.Append("<article>")
                [void]$sections.Append("<span class=`"badge $badgeCls`">$badgeTxt</span>")
                [void]$sections.Append("<a href=`"$safeUrl`" target=`"_blank`">$safeTitle</a>")
                [void]$sections.Append("<div class=`"meta`">$safeSource &nbsp;|&nbsp; $($a.time)</div>")
                if ($safeDesc) { [void]$sections.Append("<p>$safeDesc</p>") }
                [void]$sections.Append("</article>")
            }
        }
        if ($block.summary) {
            $safeSummary = HtmlEnc $block.summary
            [void]$sections.Append("<div class=`"ai`"><span>AI Summary</span>$safeSummary</div>")
        }
        [void]$sections.Append("</section>")
    }
    $ep      = if ($TopHeadlines) { "Top Headlines" } else { "Everything" }
    $tagList = $Tags -join ", "
    $html = "<!DOCTYPE html><html lang=`"en`"><head><meta charset=`"UTF-8`"><meta name=`"viewport`" content=`"width=device-width,initial-scale=1,maximum-scale=1`"><title>Morning News Briefing</title><style>
*{box-sizing:border-box;margin:0;padding:0}
html{font-size:clamp(13px,1.1vw,16px)}
body{font-family:'Segoe UI',Arial,sans-serif;background:#0f1117;color:#e2e8f0;min-height:100vh;overflow-x:hidden}
header{background:linear-gradient(135deg,#1a1f2e,#252b3b);padding:clamp(14px,2.4vw,28px) clamp(12px,3.2vw,40px) clamp(12px,2vw,20px);border-bottom:2px solid #2d3748}
header h1{font-size:clamp(1rem,2.2vw,1.5rem);color:#63b3ed;letter-spacing:.8px}
header .meta{font-size:clamp(.7rem,1.2vw,.82rem);color:#718096;margin-top:6px;line-height:1.4}
main{max-width:980px;width:min(980px,96vw);margin:clamp(10px,2.3vw,30px) auto;padding:0 clamp(8px,2vw,20px) clamp(22px,4vw,60px)}
section{margin-bottom:36px}
h2{font-size:.75rem;font-weight:700;letter-spacing:2px;color:#f6ad55;border-left:3px solid #f6ad55;padding-left:10px;margin-bottom:14px}
section.recipe h2{color:#68d391;border-color:#68d391}
section.recipe article{background:#1a2e1f;border-color:#276749}
section.recipe article img{width:100%;max-height:200px;object-fit:cover;border-radius:6px;margin-bottom:10px;display:block}
section.recipe article a{color:#9ae6b4}
article{background:#1a1f2e;border:1px solid #2d3748;border-radius:8px;padding:14px 18px;margin-bottom:10px;transition:border-color .2s;position:relative}
article:hover{border-color:#4299e1}
article a{font-size:1rem;font-weight:600;color:#90cdf4;text-decoration:none;line-height:1.4;display:block;margin-top:4px;word-break:break-word}
article a:hover{color:#63b3ed;text-decoration:underline}
.meta{font-size:.74rem;color:#718096;margin-top:5px}
article p{font-size:.85rem;color:#a0aec0;margin-top:7px;line-height:1.5;word-break:break-word}
.badge{font-size:.62rem;font-weight:700;padding:1px 7px;border-radius:3px;letter-spacing:.5px;float:right;margin-top:2px;max-width:45%}
.badge.api{background:#2a4365;color:#90cdf4}
.badge.hn{background:#7b341e;color:#fbd38d}
.ai{background:#2d1f4e;border:1px solid #553c9a;border-radius:8px;padding:12px 16px;margin-top:10px;font-size:.88rem;color:#d6bcfa;line-height:1.5}
.ai span{display:inline-block;background:#553c9a;color:#fff;font-size:.68rem;font-weight:700;letter-spacing:1px;padding:2px 8px;border-radius:4px;margin-right:8px;vertical-align:middle}
.none{color:#718096;font-style:italic;font-size:.9rem}
footer{text-align:center;color:#4a5568;font-size:.75rem;padding:20px}
@media (max-width: 780px){
section{margin-bottom:20px}
h2{font-size:.72rem;letter-spacing:1px;margin-bottom:10px}
article{padding:10px 12px;border-radius:7px}
.badge{float:none;display:inline-block;margin:0 0 6px 0}
.meta{font-size:.7rem}
footer{padding:14px}
}
</style></head><body>
<header><h1>Morning News Briefing</h1><div class=`"meta`">$timestamp &nbsp;|&nbsp; $ep &nbsp;|&nbsp; Tags: $tagList</div></header>
<main>$recipeHtml$($sections.ToString())</main>
<footer>Generated by newsUpdate.ps1 - Sources: NewsAPI.org + Hacker News Algolia</footer>
</body></html>"
    $htmlPath = Join-Path $env:TEMP ("news_" + (Get-Date).ToString("yyyyMMdd_HHmm") + ".html")
    [System.IO.File]::WriteAllText($htmlPath, $html, [System.Text.Encoding]::UTF8)
    Start-Process $htmlPath
    Write-Color "  Browser opened: $htmlPath" DarkCyan
}