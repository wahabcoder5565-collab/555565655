import type { Metadata } from "next";
import { listQuestions } from "@/lib/rq/staff";
import { QuestionEditor } from "@/components/question-editor";

export const metadata: Metadata = { title: "Questions" };

export default async function QuestionsPage() {
  const questions = await listQuestions();

  return (
    <div>
      <h1 className="text-2xl font-bold tracking-tight">Questions</h1>
      <p className="mt-1 text-sm text-slate-600">
        The wizard renders these in order. Answers are validated and coerced by
        Postgres against this definition, so a customer cannot submit a value
        the engine has not been told about.
      </p>
      <QuestionEditor questions={questions} />
    </div>
  );
}
