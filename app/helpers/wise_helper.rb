module WiseHelper
  def monthwise(year_css_class, month_css_class, title_css_class)
    years = Hash.new{|k, v| k[v] = Hash.new{|l, w| l[w] = []}}
    dated = Post.all do |page|
      page._meta_data.has_key?("yearmonth")
    end
    Post.all.each do |res|
      link, title = post_path(res), res.title
      years[res.updated_at.year][res.created_at.month] << [link, title]
    end
    html = ""
    years.sort.reverse.each do |year, months|
      html += %Q[<p class="#{year_css_class}">#{year}</p>]
      months.sort.reverse.each do |month, links|
        links.sort!{|a, b| a[1] <=> b[1]}
        links.map!{|lt| link, title = lt; %Q[<li><a href="#{link}">#{title}</a></li>] }
        month_name = Date::MONTHNAMES[month]
    html+=<<EOF
      <p class="#{month_css_class}">#{month_name}</p>
      <div class="#{title_css_class}">
        <ul>
          #{links.join("\n")}
       </ul>
      </div>
EOF
      end
    end
    html
  end

  # method show list of Articles group by tags.
  # tag_css_class - CSS class for tile of tag.
  # post_css_class - CSS class for wrapper of link and title of post.
  def tagwise(tag_css_class, post_css_class)
    html = " "
    Rails.cache.fetch("posts_by_tags") do
      Post.where.not(tag: nil).pluck(:tag).uniq.each do |tag|
        html += %Q[<p class="#{tag_css_class}">#{tag}</p>]
        Post.where(tag: tag).each do |post|
          html+= %Q[
            <div class="#{post_css_class}">
              <ul>
                <li><a href="#{post_path(post)}">#{post.title}</a></li>
             </ul>
            </div>
          ]
        end
      end
      html
    end
  end
end


