using BrokenRecord: BrokenRecord, HTTP, playback
using Dates: Day, UTC, now
using RegistryCI: TagBot
using SimpleMock: Mock, called_with, mock
using Test: @test, @testset, @test_logs

const TB = TagBot
const GH = TB.GH

TB.AUTH[] = GH.OAuth2(get(ENV, "GITHUB_TOKEN", "abcdef"))
BrokenRecord.configure!(;
    path=joinpath(@__DIR__, "cassettes"),
    ignore_headers=["Authorization"],
)

@testset "is_merged_pull_request" begin
    @test !TB.is_merged_pull_request(Dict())
    @test !TB.is_merged_pull_request(Dict("pull_request" => Dict("merged" => false)))
    @test TB.is_merged_pull_request(Dict("pull_request" => Dict("merged" => true)))
end

@testset "is_cron" begin
    withenv(() -> @test(!TB.is_cron(())), "GITHUB_EVENT_NAME" => nothing)
    withenv(() -> @test(!TB.is_cron(())), "GITHUB_EVENT_NAME" => "pull_request")
    withenv(() -> @test(TB.is_cron(())), "GITHUB_EVENT_NAME" => "schedule")
end

@testset "repo_and_version_of_pull_request" begin
    body(url) = """
        - Repository: $url
        - Version: v1.2.3
        """
    github = body("https://github.com/Foo/Bar")
    @test TB.repo_and_version_of_pull_request_body(github) == ("Foo/Bar", "v1.2.3")
    ssh = body("git@github.com:Foo/Bar.git")
    @test TB.repo_and_version_of_pull_request_body(ssh) == ("Foo/Bar", "v1.2.3")
    gitlab = body("https://gitlab.com/Foo/Bar")
    @test TB.repo_and_version_of_pull_request_body(gitlab) == (nothing, "v1.2.3")
end

@testset "clone_repo" begin
    mock(run, mktempdir => Mock("a")) do run, _mktempdir
        @test TB.clone_repo("A") == "a"
        @test called_with(run, `git clone --depth=1 https://github.com/A a`)
    end
end

@testset "is_tagbot_enabled" begin
    mock(TB.clone_repo => repo -> joinpath(@__DIR__, "repos", repo)) do _clone
        @test !TB.is_tagbot_enabled("no_actions")
        @test !TB.is_tagbot_enabled("no_tagbot")
        @test TB.is_tagbot_enabled("yes_tagbot")
    end
end

@testset "get_repo_notification_issue" begin
    repo = "christopher-dG/TestRepo"
    playback("get_repo_notification_issue.bson") do
        @test_logs (:info, "Creating new notification issue") begin
            issue = TB.get_repo_notification_issue(repo)
            @test issue.number == 4
        end
        @test_logs (:info, "Found existing notification issue") begin
            issue = TB.get_repo_notification_issue(repo)
            @test issue.number == 4
        end
    end
end

@testset "notification_body" begin
    base = "Triggering TagBot for merged registry pull request"
    @test TB.notification_body(Dict()) == base
    event = Dict("pull_request" => Dict("html_url" => "foo"))
    @test TB.notification_body(event) == "$base: foo"
end

@testset "notify" begin
    playback("notify.bson") do
        comment = TB.notify("christopher-dG/TestRepo", 4, "test notification")
        @test comment.body == "test notification"
    end
end

@testset "collect_pulls" begin
    pulls = playback("collect_pulls.bson") do
        TB.collect_pulls("JuliaRegistries/General")
    end
    @test length(pulls) == 55
    @test all(map(p -> p.merged_at !== nothing, pulls))
end

@testset "tag_exists" begin
    playback("tag_exists.bson") do
        @test TB.tag_exists("JuliaRegistries/RegistryCI.jl", "v0.1.0")
        @test !TB.tag_exists("JuliaRegistries/RegistryCI.jl", "v0.0.0")
    end
end


@testset "handle_merged_pull_request" begin
end

@testset "handle_cron" begin
end

@testset "maybe_notify" begin
    # mock(
    #     TB.clone_repo => repo -> joinpath(@__DIR__, "repos", repo),
    #     TB.tag_exists => (r, v) -> true,
    #     TB.get_repo_notification_issue,
    #     TB.notify,
    # ) do _clone, tag_exists, get_issue, notify
    #     @test_logs match_mode=:any (:info, r"not enabled") TB.maybe_notify((), "no_tagbot", "0")
    #     @test ncalls(get_issue) == 0
    #     @test_logs match_mode=:any (:info, r"already exists") TB.maybe_notify((), "yes_tagbot", "1"; check=true)
    #     @test ncalls(get_issue) == 0
    #     TB.maybe_notify(Dict(), "yes_tagbot", "2")
    #     @test called_with(get_issue, "yes_tagbot")
    # end
end
