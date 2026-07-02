module ElectionsHelper
  ELECTION_KIND_LABELS = {
    "school_council" => "전교임원선거",
    "school_council_single_contest" => "전교임원선거(단일)"
  }.freeze

  def election_kind_label(election)
    ELECTION_KIND_LABELS.fetch(election.kind, election.kind)
  end

  def election_kind_badge(election)
    content_tag(:span, election_kind_label(election), class: "rounded-md border border-indigo-200 bg-indigo-50 px-2 py-1 text-sm font-medium text-indigo-700")
  end
end
