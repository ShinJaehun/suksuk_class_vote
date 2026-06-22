module ApplicationHelper
  def kst_datetime(time)
    return "-" if time.blank?

    time.in_time_zone("Asia/Seoul").strftime("%Y-%m-%d %H:%M")
  end
end
