#!/bin/bash
# -----------------------------------------------
#  newsUpdate.sh - Personalized News Summary (Bash/Linux)
# -----------------------------------------------

# Color codes for terminal output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
DARK_GRAY='\033[0;90m'
GRAY='\033[0;37m'
DARK_CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Default parameters
NEWS_API_KEY="${NEWS_API_KEY:-}"
DISABLE_HACKER_NEWS=false
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
TAGS=("technology" "space" "AI" "gaming" "science" "OpenAI")
ARTICLES_PER_TAG=3
LANGUAGE="en"
TOP_HEADLINES=false
NO_COLOR=false
SAVE_TO_FILE=false
OUTPUT_PATH=""
OPEN_IN_BROWSER=false
BROWSER_ONLY=false
NO_BROWSER=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -NewsApiKey) NEWS_API_KEY="$2"; shift 2 ;;
        -DisableHackerNews) DISABLE_HACKER_NEWS=true; shift ;;
        -GitHubToken) GITHUB_TOKEN="$2"; shift 2 ;;
        -Tags) IFS=',' read -ra TAGS <<< "$2"; shift 2 ;;
        -ArticlesPerTag) ARTICLES_PER_TAG="$2"; shift 2 ;;
        -Language) LANGUAGE="$2"; shift 2 ;;
        -TopHeadlines) TOP_HEADLINES=true; shift ;;
        -NoColor) NO_COLOR=true; shift ;;
        -SaveToFile) SAVE_TO_FILE=true; shift ;;
        -OutputPath) OUTPUT_PATH="$2"; shift 2 ;;
        -OpenInBrowser) OPEN_IN_BROWSER=true; shift ;;
        -BrowserOnly) BROWSER_ONLY=true; shift ;;
        -NoBrowser) NO_BROWSER=true; shift ;;
        *) shift ;;
    esac
done

# Auto-open browser for interactive terminal if no explicit browser flag
if [[ -t 0 && "$OPEN_IN_BROWSER" == false && "$BROWSER_ONLY" == false && "$NO_BROWSER" == false ]]; then
    OPEN_IN_BROWSER=true
fi

# Helper functions
write_color() {
    local text="$1"
    local color="$2"
    if [[ "$BROWSER_ONLY" == true ]]; then
        return
    fi
    if [[ "$NO_COLOR" == true ]]; then
        echo "$text"
    else
        echo -e "${color}${text}${NC}"
    fi
}

html_encode() {
    local string="$1"
    string="${string//&/&amp;}"
    string="${string//</&lt;}"
    string="${string//>/&gt;}"
    string="${string//\"/&quot;}"
    string="${string//\'/&#39;}"
    echo "$string"
}

# Get daily recipe from TheMealDB
get_daily_recipe() {
    local doy=$(($(date +%j)))
    local idx=$((doy % 26))
    local letter=$(printf \\$(printf '%03o' $((97 + idx))))
    local url="https://www.themealdb.com/api/json/v1/1/search.php?f=$letter"

    local response=$(curl -s "$url" 2>/dev/null)
    if [[ -z "$response" ]]; then
        return
    fi

    # Simple JSON parsing (relies on jq if available)
    if command -v jq &>/dev/null; then
        local meal=$(echo "$response" | jq -r ".meals[$((doy % $(echo "$response" | jq '.meals | length')))]" 2>/dev/null)
        if [[ "$meal" != "null" && -n "$meal" ]]; then
            local label=$(echo "$meal" | jq -r '.strMeal')
            local url_field=$(echo "$meal" | jq -r '.strSource // .strYoutube // .strMealThumb')
            local thumb=$(echo "$meal" | jq -r '.strMealThumb')
            local cuisine=$(echo "$meal" | jq -r '.strArea')
            local category=$(echo "$meal" | jq -r '.strCategory')
            echo "$label|$url_field|$thumb|$cuisine|$category"
        fi
    fi
}

# Get news from NewsAPI
get_news_everything() {
    local tag="$1"
    local url="https://newsapi.org/v2/everything?q=$(echo "$tag" | sed 's/ /%20/g')&language=$LANGUAGE&sortBy=publishedAt&pageSize=$ARTICLES_PER_TAG&apiKey=$NEWS_API_KEY"
    curl -s "$url" 2>/dev/null
}

get_news_top_headlines() {
    local tag="$1"
    local url="https://newsapi.org/v2/top-headlines?q=$(echo "$tag" | sed 's/ /%20/g')&language=$LANGUAGE&pageSize=$ARTICLES_PER_TAG&apiKey=$NEWS_API_KEY"
    curl -s "$url" 2>/dev/null
}

# Get Hacker News articles
get_hacker_news() {
    local tag="$1"
    local url="https://hn.algolia.com/api/v1/search?query=$(echo "$tag" | sed 's/ /%20/g')&tags=story&hitsPerPage=$ARTICLES_PER_TAG"
    curl -s "$url" 2>/dev/null
}

# Validate API key
if [[ -z "$NEWS_API_KEY" ]]; then
    write_color "[!] Set your NewsAPI key via -NewsApiKey or \$NEWS_API_KEY environment variable." "$YELLOW"
    exit 1
fi

# Get recipe
RECIPE=$(get_daily_recipe)

# Fetch and display news
write_color "" "$NC"
write_color "============================================================" "$CYAN"
write_color "   [NEWS]  YOUR MORNING NEWS BRIEFING" "$CYAN"
write_color "   $(date '+%A, %d %B %Y - %H:%M')" "$CYAN"
ENDPOINT=$([ "$TOP_HEADLINES" = true ] && echo "Top Headlines" || echo "Everything")
HN_LABEL=$([ "$DISABLE_HACKER_NEWS" = true ] && echo "off" || echo "on (hn.algolia.com)")
AI_LABEL=$([ -n "$GITHUB_TOKEN" ] && echo "GitHub Copilot (gpt-4o)" || echo "off")
write_color "   NewsAPI  : $ENDPOINT  |  HN: $HN_LABEL" "$DARK_GRAY"
write_color "   Recipe   : on (TheMealDB - free)  |  AI: $AI_LABEL" "$DARK_GRAY"
write_color "============================================================" "$CYAN"

# Display recipe
if [[ -n "$RECIPE" ]]; then
    IFS='|' read -r label url_field thumb cuisine category <<< "$RECIPE"
    write_color "" "$NC"
    write_color "=== TODAY'S RECIPE RECOMMENDATION ===" "$GREEN"
    write_color "  $label" "$NC"
    write_color "  Cuisine: $cuisine  |  Category: $category" "$DARK_GRAY"
    write_color "  $url_field" "$DARK_CYAN"
    write_color "============================================================" "$GREEN"
fi

# Display articles per tag
for tag in "${TAGS[@]}"; do
    write_color "" "$NC"
    write_color "--- #${tag^^} ---" "$YELLOW"

    # NewsAPI articles
    if [ "$TOP_HEADLINES" = true ]; then
        news_response=$(get_news_top_headlines "$tag")
    else
        news_response=$(get_news_everything "$tag")
    fi

    if [[ -n "$news_response" && "$news_response" != *"error"* ]]; then
        if command -v jq &>/dev/null; then
            article_count=$(echo "$news_response" | jq '.articles | length' 2>/dev/null)
            for ((i=0; i<article_count; i++)); do
                local article=$(echo "$news_response" | jq ".articles[$i]")
                local title=$(echo "$article" | jq -r '.title' 2>/dev/null)
                local source=$(echo "$article" | jq -r '.source.name // "Unknown"' 2>/dev/null)
                local desc=$(echo "$article" | jq -r '.description // ""' 2>/dev/null | cut -c1-160)
                local url=$(echo "$article" | jq -r '.url' 2>/dev/null)
                local date_str=$(echo "$article" | jq -r '.publishedAt' 2>/dev/null)

                write_color "" "$NC"
                write_color "  * $title" "$NC"
                write_color "    [API] $source  |  $date_str" "$DARK_GRAY"
                [[ -n "$desc" ]] && write_color "    $desc" "$GRAY"
                write_color "    $url" "$DARK_CYAN"
            done
        fi
    fi

    # Hacker News articles
    if [[ "$DISABLE_HACKER_NEWS" == false ]]; then
        hn_response=$(get_hacker_news "$tag")
        if [[ -n "$hn_response" ]]; then
            if command -v jq &>/dev/null; then
                hit_count=$(echo "$hn_response" | jq '.hits | length' 2>/dev/null)
                for ((i=0; i<hit_count; i++)); do
                    local hit=$(echo "$hn_response" | jq ".hits[$i]")
                    local title=$(echo "$hit" | jq -r '.title' 2>/dev/null)
                    local hn_url=$(echo "$hit" | jq -r '.url // empty' 2>/dev/null)
                    if [[ -z "$hn_url" ]]; then
                        hn_url="https://news.ycombinator.com/item?id=$(echo "$hit" | jq -r '.objectID' 2>/dev/null)"
                    fi
                    local created=$(echo "$hit" | jq -r '.created_at' 2>/dev/null)

                    write_color "" "$NC"
                    write_color "  * $title" "$NC"
                    write_color "    [HN] Hacker News  |  $created" "$DARK_GRAY"
                    write_color "    $hn_url" "$DARK_CYAN"
                done
            fi
        fi
    fi

    write_color "" "$NC"
    write_color "------------------------------------------------------------" "$DARK_GRAY"
done

write_color "" "$NC"
write_color "  Done. Tags: $(IFS=, ; echo "${TAGS[*]}")" "$DARK_GRAY"
write_color "" "$NC"

# Browser output
if [[ "$OPEN_IN_BROWSER" == true || "$BROWSER_ONLY" == true ]]; then
    HTML_FILE="/tmp/news_$(date +%Y%m%d_%H%M).html"

    # Generate HTML (simplified)
    cat > "$HTML_FILE" << 'EOF'
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>News Briefing</title>
  <style>
    body { font-family: sans-serif; background: #0f172a; color: #e2e8f0; margin: 0; padding: 20px; }
    h1 { color: #93c5fd; }
    .article { background: #1a1f2e; border: 1px solid #334155; padding: 15px; margin: 10px 0; border-radius: 8px; }
    a { color: #60a5fa; text-decoration: none; }
    a:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <h1>Morning News Briefing</h1>
  <p>Generated on $(date)</p>
  <div class="article"><p>Open in your browser to see the full news briefing.</p></div>
</body>
</html>
EOF

    if command -v xdg-open &>/dev/null; then
        xdg-open "$HTML_FILE" 2>/dev/null
    elif command -v open &>/dev/null; then
        open "$HTML_FILE" 2>/dev/null
    fi
    write_color "  Browser opened: $HTML_FILE" "$DARK_CYAN"
fi

